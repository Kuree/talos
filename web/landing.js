const status = document.getElementById('copy-status');

// Keep the demo's place while it is offscreen or the tab is hidden.
let inView = true;
const syncVisibility = () => document.documentElement.toggleAttribute(
  'data-simulation-paused', document.hidden || !inView,
);
document.addEventListener('visibilitychange', syncVisibility);
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(([entry]) => {
    inView = entry.isIntersecting;
    syncVisibility();
  });
  observer.observe(document.querySelector('.simulation-frame'));
}
syncVisibility();

for (const button of document.querySelectorAll('[data-copy-command]')) {
  const command = document.getElementById(button.dataset.copyCommand);
  let reset;

  button.addEventListener('click', async () => {
    let copied = false;
    try {
      await navigator.clipboard.writeText(command.textContent);
      copied = true;
    } catch {
      // Select the visible command for browsers without clipboard access.
      const range = document.createRange();
      range.selectNodeContents(command);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      try {
        copied = document.execCommand('copy');
      } catch {
        // Leave the command selected so it can still be copied manually.
      }
    }

    clearTimeout(reset);
    button.classList.toggle('copied', copied);
    status.textContent = copied ? 'Command copied.' : 'Select and copy the command.';
    if (copied) reset = setTimeout(() => button.classList.remove('copied'), 1500);
  });
}
