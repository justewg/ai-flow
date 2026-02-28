// Minimal JS: reveal-on-scroll + intro hero motion
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

  // Intro hero: enter-state + subtle pointer parallax on desktop
  const intro = document.getElementById('intro');
  const heroImage = intro?.querySelector('.hero-image');
  if (intro) {
    requestAnimationFrame(() => intro.classList.add('is-ready'));
  }

  const desktopMq = window.matchMedia('(min-width: 769px)');
  if (intro && heroImage && desktopMq.matches && !prefersReduced) {
    let rafId = 0;
    let nextX = 0;
    let nextY = 0;

    const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
    const applyParallax = () => {
      heroImage.style.setProperty('--hero-translate-x', `${nextX.toFixed(2)}px`);
      heroImage.style.setProperty('--hero-translate-y', `${nextY.toFixed(2)}px`);
      rafId = 0;
    };

    const onPointerMove = (event) => {
      if (event.pointerType && event.pointerType !== 'mouse') return;
      const rect = intro.getBoundingClientRect();
      if (!rect.width || !rect.height) return;

      const dx = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
      const dy = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
      nextX = clamp(dx * 7, -7, 7);
      nextY = clamp(dy * 7, -7, 7);

      if (!rafId) {
        rafId = requestAnimationFrame(applyParallax);
      }
    };

    const onPointerLeave = () => {
      nextX = 0;
      nextY = 0;
      if (!rafId) {
        rafId = requestAnimationFrame(applyParallax);
      }
    };

    intro.addEventListener('pointermove', onPointerMove, { passive: true });
    intro.addEventListener('pointerleave', onPointerLeave, { passive: true });
  }
})();
