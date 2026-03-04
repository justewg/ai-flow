// Minimal JS: reveal-on-scroll + intro hero motion
(() => {
  const prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const preloadedSources = new Set();
  const preloadImageSource = (src) => {
    if (!src || preloadedSources.has(src)) return;
    preloadedSources.add(src);
    const probe = new Image();
    probe.decoding = 'sync';
    probe.loading = 'eager';
    probe.src = src;
  };

  const warmUpPrintImages = () => {
    const images = Array.from(document.querySelectorAll('img'));
    for (const image of images) {
      image.loading = 'eager';
      image.decoding = 'sync';
      image.fetchPriority = 'high';
      preloadImageSource(image.currentSrc || image.getAttribute('src'));
      if (!image.complete) image.decode?.().catch(() => {});
    }
  };

  const schedulePrintWarmup = () => {
    [0, 120, 420, 1200].forEach((delay) => {
      window.setTimeout(warmUpPrintImages, delay);
    });
  };

  window.addEventListener('beforeprint', schedulePrintWarmup);
  const printMq = window.matchMedia?.('print');
  if (printMq) {
    const onPrintModeChange = (event) => {
      if (event.matches) schedulePrintWarmup();
    };
    if (typeof printMq.addEventListener === 'function') {
      printMq.addEventListener('change', onPrintModeChange);
    } else if (typeof printMq.addListener === 'function') {
      printMq.addListener(onPrintModeChange);
    }
  }
  window.addEventListener('load', schedulePrintWarmup, { once: true });

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

  // Gesture before/after slider (mouse + touch via pointer events)
  const beforeAfterSliders = Array.from(document.querySelectorAll('[data-before-after]'));
  if (beforeAfterSliders.length) {
    const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
    const readInitialPosition = (slider) => {
      const raw = Number.parseFloat(slider.dataset.initial || '');
      return Number.isFinite(raw) ? clamp(raw, 5, 95) : 16;
    };
    const setSliderPosition = (slider, percent) => {
      const safePercent = clamp(percent, 0, 100);
      slider.style.setProperty('--before-after-pos', `${safePercent.toFixed(2)}%`);
      slider.dataset.position = safePercent.toFixed(2);
    };
    const getPositionFromClientX = (slider, clientX) => {
      const rect = slider.getBoundingClientRect();
      if (!rect.width) return readInitialPosition(slider);
      return ((clientX - rect.left) / rect.width) * 100;
    };

    for (const slider of beforeAfterSliders) {
      let activePointerId = null;
      const divider = slider.querySelector('.before-after__divider');

      setSliderPosition(slider, readInitialPosition(slider));

      const stopDragging = () => {
        activePointerId = null;
        slider.classList.remove('is-dragging');
      };

      const onPointerDown = (event) => {
        if (event.button !== undefined && event.button !== 0) return;
        activePointerId = event.pointerId;
        slider.classList.add('is-dragging');
        slider.classList.remove('is-hinting');
        slider.dataset.interacted = '1';
        setSliderPosition(slider, getPositionFromClientX(slider, event.clientX));
        slider.setPointerCapture?.(event.pointerId);
        event.preventDefault();
      };

      const onPointerMove = (event) => {
        if (activePointerId === null || event.pointerId !== activePointerId) return;
        setSliderPosition(slider, getPositionFromClientX(slider, event.clientX));
      };

      const onPointerUp = (event) => {
        if (activePointerId === null || event.pointerId !== activePointerId) return;
        stopDragging();
      };

      slider.addEventListener('pointerdown', onPointerDown);
      slider.addEventListener('pointermove', onPointerMove);
      slider.addEventListener('pointerup', onPointerUp);
      slider.addEventListener('pointercancel', onPointerUp);
      slider.addEventListener('lostpointercapture', stopDragging);
      window.addEventListener('pointerup', onPointerUp, { passive: true });
      window.addEventListener('pointercancel', onPointerUp, { passive: true });

      divider?.addEventListener('keydown', (event) => {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        const current = Number.parseFloat(slider.dataset.position || `${readInitialPosition(slider)}`);
        const next = event.key === 'ArrowLeft' ? current - 4 : current + 4;
        setSliderPosition(slider, next);
        slider.dataset.interacted = '1';
        slider.classList.remove('is-hinting');
        event.preventDefault();
      });
    }

    if ('IntersectionObserver' in window && !prefersReduced) {
      const hintObserver = new IntersectionObserver((entries, observer) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const slider = entry.target;
          if (slider.dataset.interacted === '1') {
            observer.unobserve(slider);
            continue;
          }
          slider.classList.add('is-hinting');
          window.setTimeout(() => slider.classList.remove('is-hinting'), 950);
          observer.unobserve(slider);
        }
      }, { rootMargin: '0px 0px -12% 0px', threshold: 0.25 });

      beforeAfterSliders.forEach(slider => hintObserver.observe(slider));
    }
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
