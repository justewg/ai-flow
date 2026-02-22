// Minimal JS: reveal-on-scroll + subtle parallax
(() => {
  const prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Reveal on scroll using IntersectionObserver
  const revealEls = Array.from(document.querySelectorAll('.reveal'));
  if ('IntersectionObserver' in window && revealEls.length && !prefersReduced) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          io.unobserve(entry.target);
        }
      }
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.1 });
    revealEls.forEach(el => {
      const anim = el.getAttribute('data-animate');
      if (anim === 'slide') el.classList.add('slide');
      io.observe(el);
    });
  } else {
    // Fallback: show all
    revealEls.forEach(el => el.classList.add('in-view'));
  }

  // Subtle parallax for intro hero
  const parallaxEls = Array.from(document.querySelectorAll('.parallax'));
  if (parallaxEls.length && !prefersReduced) {
    const onScroll = () => {
      for (const el of parallaxEls) {
        const speed = parseFloat(el.dataset.parallax || '0.15');
        const rect = el.getBoundingClientRect();
        const vh = window.innerHeight || document.documentElement.clientHeight;
        if (rect.bottom < 0 || rect.top > vh) continue; // skip offscreen
        // progress within viewport (0 at top enter, 1 at bottom leave)
        const center = rect.top + rect.height / 2;
        const progress = (center - vh / 2) / vh; // -0.5..0.5 roughly
        const translate = Math.max(-20, Math.min(20, progress * speed * 120)); // clamp ±20px
        el.style.transform = `translateY(${translate}px)`;
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    onScroll();
  }
})();

