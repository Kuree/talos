//===- CanonicalPlane.h - Owned or generated state storage -------*- C++
//-*-===//

#ifndef TALOS_RUNTIME_LIB_CANONICALPLANE_H
#define TALOS_RUNTIME_LIB_CANONICALPLANE_H

#include "ExceptionSupport.h"
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <memory>

// Generated planes are byte arrays. The alias-qualified limb also permits
// their use by runtime code when the model and runtime are linked with LTO.
#if defined(__GNUC__) || defined(__clang__)
using CanonicalLimb = uint64_t __attribute__((__may_alias__));
#else
using CanonicalLimb = uint64_t;
#endif

class CanonicalPlane {
public:
  // A known-zero plane retains its logical extent without allocating bytes.
  // Scalar clients may read it as zero; writes cannot create unknown state.
  class Reference {
  public:
    explicit Reference(CanonicalLimb *word) : word(word) {}
    operator uint64_t() const { return word ? *word : 0; }
    Reference &operator=(uint64_t value) {
      if (word)
        *word = value;
      return *this;
    }
    Reference &operator=(const Reference &other) {
      return *this = uint64_t(other);
    }
    Reference &operator|=(uint64_t value) {
      return *this = uint64_t(*this) | value;
    }
    Reference &operator&=(uint64_t value) {
      return *this = uint64_t(*this) & value;
    }
    Reference &operator^=(uint64_t value) {
      return *this = uint64_t(*this) ^ value;
    }

  private:
    CanonicalLimb *word;
  };
  void assignZero(size_t count) {
    bind(nullptr, count);
    shared_ = false;
  }
  void assign(size_t count, uint64_t value) {
    // Large simulation memories can stay backed by the system's zero page
    // until actually written or rebound to the generated state image.
    bool fresh = reserveOwned(count, value == 0);
    if (count && (value || !fresh))
      std::fill_n(owned.get(), count, value);
    words = owned.get();
    count_ = count;
    shared_ = false;
  }
  void bind(uint8_t *plane, size_t count) {
    owned.reset();
    capacity = 0;
    words = reinterpret_cast<CanonicalLimb *>(plane);
    count_ = count;
    shared_ = true;
  }
  bool shared() const { return shared_; }
  void swap(CanonicalPlane &other) noexcept {
    owned.swap(other.owned);
    std::swap(capacity, other.capacity);
    std::swap(words, other.words);
    std::swap(count_, other.count_);
    std::swap(shared_, other.shared_);
  }
  size_t size() const { return count_; }
  bool empty() const { return !count_; }
  CanonicalLimb *data() { return words; }
  const CanonicalLimb *data() const { return words; }
  CanonicalLimb *begin() { return words; }
  CanonicalLimb *end() { return words ? words + count_ : words; }
  const CanonicalLimb *begin() const { return words; }
  const CanonicalLimb *end() const { return words ? words + count_ : words; }
  Reference operator[](size_t index) {
    return Reference(words ? words + index : nullptr);
  }
  uint64_t operator[](size_t index) const { return words ? words[index] : 0; }
  Reference front() { return (*this)[0]; }
  uint64_t front() const { return (*this)[0]; }
  Reference back() { return (*this)[count_ - 1]; }
  uint64_t back() const { return (*this)[count_ - 1]; }

  CanonicalPlane() = default;
  CanonicalPlane(CanonicalPlane &&other) noexcept { swap(other); }
  CanonicalPlane &operator=(CanonicalPlane &&other) noexcept {
    CanonicalPlane moved;
    moved.swap(other);
    swap(moved);
    return *this;
  }
  CanonicalPlane(const CanonicalPlane &other) { *this = other; }
  CanonicalPlane &operator=(const CanonicalPlane &other) {
    if (this != &other) {
      if (!other.words) {
        assignZero(other.count_);
        return *this;
      }
      reserveOwned(other.count_, false);
      std::copy_n(other.words, other.count_, owned.get());
      words = owned.get();
      count_ = other.count_;
      shared_ = false;
    }
    return *this;
  }
  bool operator==(const CanonicalPlane &other) const {
    if (size() != other.size())
      return false;
    for (size_t index = 0; index != size(); ++index)
      if ((*this)[index] != other[index])
        return false;
    return true;
  }

private:
  struct Free {
    void operator()(uint64_t *p) const { std::free(p); }
  };
  bool reserveOwned(size_t count, bool zero) {
    if (count <= capacity)
      return false;
    if (count > std::numeric_limits<size_t>::max() / sizeof(uint64_t))
      talos_rt_out_of_memory();
    auto *p =
        static_cast<uint64_t *>(zero ? std::calloc(count, sizeof(uint64_t))
                                     : std::malloc(count * sizeof(uint64_t)));
    if (!p)
      talos_rt_out_of_memory();
    owned.reset(p);
    capacity = count;
    return true;
  }
  std::unique_ptr<uint64_t, Free> owned;
  size_t capacity = 0;
  CanonicalLimb *words = nullptr;
  size_t count_ = 0;
  bool shared_ = false;
};

#endif
