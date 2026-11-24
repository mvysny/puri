/**
 * Every terminal's Copy button: copies the commands of its own block, one per line, without the
 * `$ ` prompts or the `#` comments.
 *
 *     <div class="term"><div class="term-head">Terminal<button class="copy">Copy</button></div>
 *     <pre><span class="p">$ </span><span class="cmd">git pull</span></pre></div>
 *
 * Markup contract: a `.term` with a `.copy` button holds one `pre`, whose `.cmd` spans are the
 * commands; a `.term` without a button is skipped.
 */
document.querySelectorAll('.term').forEach((term) => {
  const button = term.querySelector('.copy');
  if (!button) return;
  const pre = term.querySelector('pre');
  button.addEventListener('click', async () => {
    const text = [...pre.querySelectorAll('.cmd')].map((el) => el.textContent).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = 'Copied';
    } catch {
      // No clipboard on a plain-http preview, or the browser said no: select it for Ctrl+C.
      getSelection().selectAllChildren(pre);
      button.textContent = 'Press Ctrl+C';
    }
    setTimeout(() => { button.textContent = 'Copy'; }, 2000);
  });
});
