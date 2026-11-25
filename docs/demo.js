// The front page's script: replays three invented conversations in the hero's popup, in the
// wording Puri uses for its steps (dev/puri/dummy/script.rb), and thickens a diagram line while
// its table row is pointed at. copy.js, beside it, does the terminal's Copy button.
//
// The replay is the page's whole demo: there's no video (owner, 2026-11-25).
//
// The popup opens on the first conversation finished, so the page reads complete before anything
// moves, and stays there under reduced motion.
//
// Markup contract: #puri-template, [data-replay] and .diagram must exist; a missing one throws at
// load. style.css draws what this toggles: data-state on
// .puri-win (pill, open), .down on the shortcut's kbd and the popup's button, .hot on a diagram
// group.
(() => {
  const STOP = Symbol('stop');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const SCENES = [
    { q: "What's the weather on my Lisbon trip?", title: 'Weather on My Lisbon Trip', steps: [
      ['think', 'Reading your calendar…'],
      ['tool', '📅 Read calendar: Lisbon trip, Thu 3 – Mon 7 Dec'],
      ['think', 'Checking the weather…'],
      ['tool', '🌦 Weather from <a href="https://open-meteo.com/">Open-Meteo</a>: Lisbon'],
      ['say', 'Your **Lisbon** trip runs from **Thursday 3** to **Monday 7 December**. Mild and mostly dry, **14 to 17 °C**, with showers likely on **Saturday afternoon**, so pack an umbrella.'],
    ] },
    { q: "Tell Jana I'll be 10 minutes late", title: 'Running Late for Jana', steps: [
      ['think', 'Reading your calendar…'],
      ['tool', '📅 Read calendar: Work, today'],
      ['think', 'Writing the draft…'],
      ['say', "You meet **Jana** at **14:00** for the design review. Here's a draft:"],
      ['quote', "Hi Jana, I'm running about ten minutes late. See you at 14:10!"],
      ['confirm', 'Open this draft to Jana in your mail app? Nothing is sent until you send it.', 'Open draft'],
      ['tool', '✉️ Opened draft: To Jana, “Running late”'],
      ['say', 'The draft is open in your mail app.'],
    ] },
    { q: "How much was the plumber's invoice?", title: "The Plumber's Invoice", steps: [
      ['think', 'Searching your documents…'],
      ['tool', '🗂 Searched documents: plumber invoice'],
      ['think', 'Reading a document…'],
      ['tool', '📄 Read: Invoices/2026-10 Kallio LVI.pdf'],
      ['say', '**€340.00**, from **Kallio LVI** on 14 October, due by 13 November. It covers a new kitchen tap and two hours of work.'],
    ] },
  ];

  class Replay {
    constructor(root, keys) {
      root.append(document.getElementById('puri-template').content.cloneNode(true));
      this.root = root;
      this.keys = keys;
      this.win = root.querySelector('.puri-win');
      this.title = root.querySelector('.puri-title');
      this.tx = root.querySelector('.puri-tx');
      this.input = root.querySelector('.puri-input');
      this.cursor = root.querySelector('.puri-cursor');
      this.gen = 0;
      this.finished(SCENES[0]);
    }

    wait(ms) {
      const gen = this.gen;
      return new Promise((resolve, reject) => setTimeout(() => (gen === this.gen ? resolve() : reject(STOP)), ms));
    }

    stop() { this.gen++; }

    async start() {
      this.stop();
      this.finished(SCENES[0]);
      if (reduced) return;
      try {
        await this.wait(2800);
        for (let i = 1; ; i++) await this.play(SCENES[i % SCENES.length]);
      } catch (e) {
        if (e !== STOP) throw e;
      }
    }

    toBottom() { this.tx.scrollTop = this.tx.scrollHeight; }

    add(cls, html) {
      const el = document.createElement('div');
      el.className = `${cls} puri-fade`;
      if (html != null) el.innerHTML = html;
      this.tx.append(el);
      this.toBottom();
      return el;
    }

    finished(scene) {
      this.win.dataset.state = 'open';
      this.title.textContent = scene.title;
      this.input.textContent = '';
      this.tx.replaceChildren();
      this.add('puri-user').textContent = scene.q;
      for (const [kind, text] of scene.steps) {
        if (kind === 'tool') this.add('puri-tool', text);
        else if (kind === 'say') this.add('puri-reply', text.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>'));
        else if (kind === 'quote') this.add('puri-quote').textContent = text;
      }
      this.tx.scrollTop = 0;
      this.tx.querySelectorAll('.puri-fade').forEach((el) => el.classList.remove('puri-fade'));
    }

    async stream(el, text) {
      let target = el;
      for (const part of text.split(/(\*\*)/)) {
        if (part === '**') {
          if (target === el) {
            target = document.createElement('strong');
            el.append(target);
          } else target = el;
          continue;
        }
        for (const word of part.split(/(\s+)/)) {
          if (!word) continue;
          target.append(word);
          if (/\S/.test(word)) {
            this.toBottom();
            await this.wait(34 + Math.random() * 46);
          }
        }
      }
    }

    async click(button) {
      const box = this.root.getBoundingClientRect();
      const b = button.getBoundingClientRect();
      const c = this.cursor;
      c.style.transition = 'none';
      c.style.transform = `translate(${box.width - 30}px, ${box.height + 10}px)`;
      c.getBoundingClientRect();
      c.style.transition = '';
      c.style.opacity = '1';
      c.style.transform = `translate(${b.left - box.left + b.width / 2}px, ${b.top - box.top + b.height / 2}px)`;
      await this.wait(1150);
      button.classList.add('down');
      await this.wait(160);
      button.classList.remove('down');
      await this.wait(220);
      c.style.opacity = '0';
    }

    async step([kind, text, action]) {
      if (kind === 'think') {
        const el = this.add('puri-think', '<span class="puri-spin"></span>');
        el.append(text);
        await this.wait(1150);
        el.remove();
      } else if (kind === 'tool') {
        this.add('puri-tool', text);
        await this.wait(380);
      } else if (kind === 'say' || kind === 'quote') {
        await this.stream(this.add(kind === 'say' ? 'puri-reply' : 'puri-quote'), text);
        await this.wait(300);
      } else if (kind === 'confirm') {
        const card = this.add('puri-confirm');
        card.innerHTML = '<div></div><div class="puri-confirm-btns"><span class="puri-b">Cancel</span><span class="puri-b suggested"></span></div>';
        card.firstChild.textContent = text;
        card.querySelector('.suggested').textContent = action;
        this.toBottom();
        await this.wait(900);
        await this.click(card.querySelector('.suggested'));
        card.remove();
      }
    }

    async play(scene) {
      this.win.dataset.state = 'pill';
      await this.wait(520);
      this.tx.replaceChildren();
      this.title.textContent = '';
      this.keys.forEach((k) => k.classList.add('down'));
      await this.wait(180);
      this.keys.forEach((k) => k.classList.remove('down'));
      await this.wait(500);
      for (const ch of scene.q) {
        this.input.textContent += ch;
        await this.wait(32 + Math.random() * 58);
      }
      await this.wait(500);
      this.input.textContent = '';
      this.title.textContent = scene.title;
      this.win.dataset.state = 'open';
      this.add('puri-user').textContent = scene.q;
      await this.wait(650);
      for (const s of scene.steps) await this.step(s);
      await this.wait(4200);
    }
  }

  const root = document.querySelector('[data-replay]');
  const replay = new Replay(root, [...document.querySelectorAll('.keys kbd')]);
  // Plays only while on screen; scrolling back starts it over.
  new IntersectionObserver(([entry]) => (entry.isIntersecting ? replay.start() : replay.stop()), { threshold: 0.3 }).observe(root);

  const diagram = document.querySelector('.diagram');
  // Too narrow for the whole drawing, open it on the lines that leave: that half is the point.
  const frame = diagram.parentElement;
  frame.scrollLeft = frame.scrollWidth;
  document.querySelectorAll('tr[data-flow]').forEach((row) => {
    const line = diagram.querySelector(`g[data-flow="${row.dataset.flow}"]`);
    row.addEventListener('mouseenter', () => line.classList.add('hot'));
    row.addEventListener('mouseleave', () => line.classList.remove('hot'));
  });
})();
