{{-- "Today at Rehab+": the viewer for pictures the clinic shares today. It opens from the logo's ring in the hero, so nothing is shown in the page itself. Needs $stories from LandingController. --}}
@if (! empty($stories))
    <style>
        /* The logo's ring: the same look as a story ring, shown only when there are pictures for today. */
        /* A ring that turns slowly around the logo. The gradient sits behind the logo and rotates. */
        /* The logo is a square button, so the ring is a true circle. The logo's own bottom margin moves to the button. */
        .home-hero-logo-btn { position: relative; isolation: isolate; display: block; width: 104px; height: 104px; margin: 0 auto 1.25rem; padding: 0; border: 0; border-radius: 50%; background: none; cursor: pointer; transition: transform .2s ease; }
        .home-hero-logo-btn .home-hero-logo { display: block; width: 100%; height: 100%; margin: 0; }
        .home-hero-logo-btn:hover, .home-hero-logo-btn:focus-visible { transform: scale(1.04); }
        .home-hero-logo-btn:focus-visible { outline: 3px solid #fff; outline-offset: 6px; }
        /* The ring turns slowly around the logo, only when there are pictures posted today. */
        .home-hero-logo-btn.is-new::before { content: ''; position: absolute; inset: -6px; border-radius: 50%; background: conic-gradient(#5eead4, #14b8a6, #0f766e, #99f6e4, #5eead4); z-index: -1; animation: today-ring-spin 4s linear infinite; }
        @keyframes today-ring-spin { to { transform: rotate(360deg); } }

        .today-dialog { width: min(680px, 94vw); max-height: 92vh; border: 0; border-radius: 1.1rem; padding: 0; overflow: hidden; box-shadow: 0 30px 60px rgba(15, 23, 42, .4); background: #fff; color: #0f172a; }
        .today-dialog::backdrop { background: rgba(15, 23, 42, .7); }
        .today-dialog-wrap { position: relative; display: flex; flex-direction: column; }
        .today-stage { position: relative; background: #0f172a; display: flex; align-items: center; justify-content: center; min-height: 300px; }
        .today-stage img { display: block; max-width: 100%; max-height: 66vh; width: auto; height: auto; object-fit: contain; }
        .today-nav { position: absolute; top: 50%; transform: translateY(-50%); width: 2.6rem; height: 2.6rem; border-radius: 50%; border: 0; background: rgba(255, 255, 255, .85); color: #0f172a; font-size: 1.5rem; line-height: 1; cursor: pointer; box-shadow: 0 4px 12px rgba(0, 0, 0, .25); }
        .today-nav:disabled { opacity: .35; cursor: default; }
        .today-prev { left: .6rem; }
        .today-next { right: .6rem; }
        .today-close { position: absolute; top: .6rem; right: .6rem; z-index: 2; width: 2.2rem; height: 2.2rem; border-radius: 50%; border: 0; background: rgba(15, 23, 42, .7); color: #fff; font-size: 1.2rem; line-height: 1; cursor: pointer; }
        .today-body { padding: 1rem 1.25rem 1.25rem; }
        .today-kicker { margin: 0 0 .15rem; font-size: .72rem; font-weight: 800; letter-spacing: .09em; text-transform: uppercase; color: #0f766e; }
        .today-title { margin: 0 0 .25rem; font-weight: 800; font-size: 1.1rem; }
        .today-caption { margin: 0; color: #64748b; }
        .today-count { margin: .6rem 0 0; font-size: .8rem; color: #94a3b8; }
        @media (prefers-reduced-motion: reduce) { .home-hero-logo-btn, .home-hero-logo-btn.is-new::before { transition: none; animation: none; } .home-hero-logo-btn:hover { transform: none; } }
    </style>

    <div class="today-dialog-root" data-stories>
        <dialog class="today-dialog" data-story-dialog aria-label="Today at Rehab+">
            <div class="today-dialog-wrap">
                <form method="dialog"><button class="today-close" aria-label="Close">&times;</button></form>
                <div class="today-stage">
                    <button type="button" class="today-nav today-prev" data-story-prev aria-label="Previous picture">&lsaquo;</button>
                    <img src="" alt="" data-story-image>
                    <button type="button" class="today-nav today-next" data-story-next aria-label="Next picture">&rsaquo;</button>
                </div>
                <div class="today-body">
                    <p class="today-kicker">Today at Rehab+</p>
                    <p class="today-title" data-story-title></p>
                    <p class="today-caption" data-story-caption></p>
                    <p class="today-count" data-story-count></p>
                </div>
            </div>
        </dialog>
    </div>

    <script type="application/json" id="stories-data">@json($stories)</script>
    <script nonce="{{ Vite::cspNonce() }}">
        (function () {
            var root = document.querySelector('[data-stories]');
            if (!root) return;
            var stories = JSON.parse(document.getElementById('stories-data').textContent);
            var dialog = root.querySelector('[data-story-dialog]');
            var image = dialog.querySelector('[data-story-image]');
            var title = dialog.querySelector('[data-story-title]');
            var caption = dialog.querySelector('[data-story-caption]');
            var count = dialog.querySelector('[data-story-count]');
            var prev = dialog.querySelector('[data-story-prev]');
            var next = dialog.querySelector('[data-story-next]');
            var current = 0;

            function show(index) {
                if (index < 0 || index >= stories.length) return;
                current = index;
                var story = stories[current];
                image.src = story.image;
                image.alt = story.title;
                title.textContent = story.title;
                caption.textContent = story.caption || '';
                count.textContent = (current + 1) + ' of ' + stories.length;
                prev.disabled = current === 0;
                next.disabled = current === stories.length - 1;
            }

            document.querySelectorAll('[data-stories-open]').forEach(function (button) {
                button.addEventListener('click', function () {
                    show(0);
                    dialog.showModal();
                });
            });

            prev.addEventListener('click', function () { show(current - 1); });
            next.addEventListener('click', function () { show(current + 1); });

            dialog.addEventListener('keydown', function (event) {
                if (event.key === 'ArrowLeft') show(current - 1);
                if (event.key === 'ArrowRight') show(current + 1);
            });

            // A click on the backdrop (outside the picture) closes the viewer.
            dialog.addEventListener('click', function (event) {
                if (event.target === dialog) dialog.close();
            });
        })();
    </script>
@endif
