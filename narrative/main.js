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

  // Gesture "show" stage: crossfade between two images while scrolling through the stage
  const scrollFadeStacks = Array.from(document.querySelectorAll('[data-scroll-fade]'));
  if (scrollFadeStacks.length && !prefersReduced) {
    let rafId = 0;
    const clamp = (value) => Math.min(1, Math.max(0, value));

    const updateScrollFade = () => {
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 1;

      for (const stack of scrollFadeStacks) {
        const stage = stack.closest('.stage') || stack;
        const rect = stage.getBoundingClientRect();
        const totalDistance = Math.max(rect.height + viewportHeight, 1);
        const passedDistance = viewportHeight - rect.top;
        const progress = clamp(passedDistance / totalDistance);
        stack.style.setProperty('--gesture-show-alt-opacity', progress.toFixed(3));
      }

      rafId = 0;
    };

    const requestScrollFadeUpdate = () => {
      if (!rafId) {
        rafId = requestAnimationFrame(updateScrollFade);
      }
    };

    window.addEventListener('scroll', requestScrollFadeUpdate, { passive: true });
    window.addEventListener('resize', requestScrollFadeUpdate);
    requestScrollFadeUpdate();
  } else {
    scrollFadeStacks.forEach(stack => stack.style.setProperty('--gesture-show-alt-opacity', '0'));
  }

  // Intro hero: enter-state + subtle background parallax on desktop
  const intro = document.getElementById('intro');
  const introBg = intro?.querySelector('.planka-hero__bg');
  if (intro) {
    requestAnimationFrame(() => intro.classList.add('is-ready'));
  }

  const desktopMq = window.matchMedia('(min-width: 769px)');
  if (intro && introBg && desktopMq.matches && !prefersReduced) {
    let rafId = 0;
    let tx = 0;
    let ty = 0;

    const applyParallax = () => {
      introBg.style.backgroundPosition = `calc(100% + ${tx.toFixed(2)}px) calc(50% + ${ty.toFixed(2)}px)`;
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
      introBg.style.backgroundPosition = 'right center';
    };

    intro.addEventListener('pointermove', onPointerMove, { passive: true });
    intro.addEventListener('pointerleave', onPointerLeave, { passive: true });
  }
})();
