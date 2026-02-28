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

  // Intro hero: enter-state + subtle background parallax on desktop
  const intro = document.getElementById('intro');
  if (intro) {
    requestAnimationFrame(() => intro.classList.add('is-ready'));
  }

  const desktopMq = window.matchMedia('(min-width: 769px)');
  if (intro && desktopMq.matches && !prefersReduced) {
    let rafId = 0;
    let tx = 0;
    let ty = 0;

    const applyParallax = () => {
      intro.style.backgroundPosition = `calc(100% + ${tx.toFixed(2)}px) calc(50% + ${ty.toFixed(2)}px)`;
      rafId = 0;
    };

    const onPointerMove = (event) => {
      if (event.pointerType && event.pointerType !== 'mouse') return;
      const rect = intro.getBoundingClientRect();
      if (!rect.width || !rect.height) return;

      const dx = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
      const dy = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
      tx = dx * 6;
      ty = dy * 6;

      if (!rafId) {
        rafId = requestAnimationFrame(applyParallax);
      }
    };

    const onPointerLeave = () => {
      tx = 0;
      ty = 0;
      if (rafId) {
        cancelAnimationFrame(rafId);
        rafId = 0;
      }
      intro.style.backgroundPosition = 'right center';
    };

    intro.addEventListener('pointermove', onPointerMove, { passive: true });
    intro.addEventListener('pointerleave', onPointerLeave, { passive: true });
  }
})();
