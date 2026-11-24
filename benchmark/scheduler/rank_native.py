"""Optional host graph accelerator for forward_rank. The Python planner owns the objective."""

from array import array
import ctypes as ct
import os
from itertools import chain, groupby
from pathlib import Path
import sys
from weakref import finalize


def _library():
    explicit = os.environ.get("TALOS_RANK_LIBRARY")
    filename = (
        "TalosRankGraph.dll"
        if sys.platform == "win32"
        else "libTalosRankGraph.dylib"
        if sys.platform == "darwin"
        else "libTalosRankGraph.so"
    )
    path = Path(explicit) if explicit else Path(__file__).resolve().with_name(filename)
    if not explicit and not path.is_file():
        return None
    return ct.CDLL(str(path.resolve()))


lib = _library()
IntPointer = ct.POINTER(ct.c_int)
if lib:
    lib.talos_rank_free.argtypes = (ct.c_void_p,)
    lib.talos_rank_free.restype = None
    lib.talos_rank_check.argtypes = (
        ct.c_void_p,
        IntPointer,
        ct.c_int,
        ct.c_int,
        ct.c_int,
        ct.POINTER(IntPointer),
        ct.POINTER(ct.c_int),
    )
    if hasattr(lib, "talos_rank_solver"):
        lib.talos_rank_solver.argtypes = ()
        lib.talos_rank_solver.restype = ct.c_void_p
        lib.talos_rank_solver_free.argtypes = (ct.c_void_p,)
        lib.talos_rank_solver_free.restype = None
        lib.talos_rank_smt.argtypes = (ct.c_void_p, ct.c_char_p, ct.c_char_p)
        lib.talos_rank_smt.restype = ct.c_char_p


def _buffer(data):
    return (ct.c_int * len(data)).from_buffer(data)


def supports(model):
    # Native graphs use signed 32-bit indices and four integers per edge.
    # Allow for virtual kernel nodes, source equalities and kernel barriers.
    nodes = len(model.labels)
    max_arcs = 3 * len(model.control) + len(model.required) + 2 * nodes
    return (
        lib is not None
        and array("i").itemsize == ct.sizeof(ct.c_int) == 4
        and 4 * max_arcs < 2**31 - 1
    )


class Graph:
    def __init__(self, handle):
        self.handle = handle
        finalize(self, lib.talos_rank_free, handle)

    def cut_subset_graph(self, disabled):
        data = array("i", disabled)
        return Graph(lib.talos_rank_cut_subset(self.handle, _buffer(data), len(data)))

    def feasible(self, disabled):
        data = array("i", disabled)
        return bool(lib.talos_rank_feasible(self.handle, _buffer(data), len(data)))

    def check(self, disabled, witnesses, compact=False):
        data = array("i", disabled)
        values = IntPointer()
        size = ct.c_int()
        status = lib.talos_rank_check(
            self.handle,
            _buffer(data),
            len(data),
            witnesses,
            compact,
            ct.byref(values),
            ct.byref(size),
        )
        if status < 0:
            return None
        if status:
            return set()
        result = values[: size.value] if size.value else []
        clauses = set()
        start = 0
        for i, value in enumerate(result):
            if value == 0:
                clauses.add(tuple(sorted(set(result[start:i]))))
                start = i + 1
        return clauses


class Session:
    def __init__(self):
        self.handle = lib.talos_rank_solver()
        finalize(self, lib.talos_rank_solver_free, self.handle)

    def run(self, query, values):
        return lib.talos_rank_smt(
            self.handle, ("(reset)\n" + query).encode(), values.encode()
        ).decode()


if lib:
    lib.talos_rank_model.argtypes = (
        ct.c_int,
        ct.c_int,
        IntPointer,
        IntPointer,
        ct.c_int,
        IntPointer,
        ct.c_int,
        IntPointer,
        ct.c_int,
    )
    lib.talos_rank_model.restype = ct.c_void_p
    lib.talos_rank_model_free.argtypes = (ct.c_void_p,)
    lib.talos_rank_model_free.restype = None
    if hasattr(lib, "talos_rank_model_rank_first"):
        lib.talos_rank_model_rank_first.argtypes = (ct.c_void_p,)
        lib.talos_rank_model_rank_first.restype = None
        lib.talos_rank_cut_subset.argtypes = (ct.c_void_p, IntPointer, ct.c_int)
        lib.talos_rank_cut_subset.restype = ct.c_void_p
        lib.talos_rank_feasible.argtypes = (ct.c_void_p, IntPointer, ct.c_int)
    lib.talos_rank_model_graph.argtypes = (ct.c_void_p, ct.c_int)
    lib.talos_rank_model_graph.restype = ct.c_void_p
    lib.talos_rank_expand.argtypes = (ct.c_void_p, ct.c_void_p)
    lib.talos_rank_model_data.argtypes = (ct.c_void_p, ct.c_int, ct.POINTER(ct.c_int))
    lib.talos_rank_model_data.restype = IntPointer


class Topology:
    def __init__(self, model):
        owner = array("i", model.owner)
        control = array("i", chain.from_iterable(model.control))
        required = array("i", chain.from_iterable(model.required))
        hard = array("i", chain.from_iterable(model.hard))
        self.handle = lib.talos_rank_model(
            len(owner),
            len(model.names),
            _buffer(owner),
            _buffer(control),
            len(control) // 2,
            _buffer(required),
            len(required) // 2,
            _buffer(hard),
            len(hard) // 2,
        )
        finalize(self, lib.talos_rank_model_free, self.handle)
        if model.rank_first:
            lib.talos_rank_model_rank_first(self.handle)

    def data(self, field):
        n = ct.c_int()
        ptr = lib.talos_rank_model_data(self.handle, field, ct.byref(n))
        data = array("i")
        if n.value:
            data.frombytes(ct.string_at(ptr, n.value * ct.sizeof(ct.c_int)))
        return data

    def groups(self):
        items = self.data(0)
        return [list(sub) for flag, sub in groupby(items, lambda v: v != -1) if flag]

    def cycle(self):
        return list(self.data(1))

    def boundaries(self):
        return set(self.data(2))

    def graph(self, owners_only):
        return Graph(lib.talos_rank_model_graph(self.handle, owners_only))

    def expand(self, graph):
        if not lib.talos_rank_expand(self.handle, graph.handle):
            raise RuntimeError("invalid expanded native rank schedule")
        return self.data(3)

    def costs(self):
        pairs = iter(self.data(5))
        return set(self.data(4)), set(zip(pairs, pairs))
