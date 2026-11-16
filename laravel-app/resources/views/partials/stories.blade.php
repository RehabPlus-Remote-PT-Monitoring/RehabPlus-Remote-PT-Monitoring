{{-- "Today at Rehab+": pictures the clinic shares today (schedules, a moment from a session). Sits under Visit us, in the same width and style. Needs $stories from LandingController. --}}
@if (! empty($stories))
    <style>
        .today-card { background: var(--card, #fff); border: 1px solid var(--border); border-radius: 1.25rem; padding: 1.5rem; }
        .today-head { margin-bottom: 1.1rem; }
        .today-title { margin: 0 0 .2rem; font-size: 1.5rem; font-weight: 800; letter-spacing: -.01em; }
        .today-sub { margin: 0; color: var(--muted, #64748b); font-size: .95rem; }
        .today-row { display: flex; gap: 1rem; overflow-x: auto; padding: .25rem .1rem .6rem; scroll-snap-type: x proximity; }
        .today-row::-webkit-scrollbar { height: 6px; }
        .today-tile { flex: 0 0 auto; max-width: 220px; display: flex; flex-direction: column; gap: .5rem; padding: 0; background: none; border: 0; cursor: pointer; text-align: left; color: var(--text, #0f172a); scroll-snap-align: start; }
        /* The whole picture is shown, never cropped: the frame takes the picture's own proportions. */
        .today-frame { display: flex; align-items: center; justify-content: center; height: 220px; padding: .4rem; border-radius: 1rem; overflow: hidden; border: 1px solid var(--border); background: #f8fafc; box-shadow: 0 6px 16px rgba(15, 23, 42, .08); transition: transform .2s ease, box-shadow .2s ease; }
        .today-frame img { display: block; height: 100%; width: auto; max-width: 100%; object-fit: contain; border-radius: .6rem; }
        .today-tile:hover .today-frame, .today-tile:focus-visible .today-frame { transform: translateY(-3px); box-shadow: 0 12px 26px rgba(15, 23, 42, .14); }
        .today-tile:focus-visible { outline: 3px solid #5eead4; outline-offset: 4px; border-radius: 1rem; }
        .today-name { font-size: .9rem; font-weight: 700; line-height: 1.25; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .today-dialog { width: min(640px, 94vw); border: 0; border-radius: 1.1rem; padding: 0; overflow: hidden; box-shadow: 0 30px 60px rgba(15, 23, 42, .35); }
        .today-dialog::backdrop { background: rgba(15, 23, 42, .6); }
        .today-dialog-wrap { position: relative; }
        .today-dialog img { display: block; width: 100%; max-height: 72vh; object-fit: contain; background: #f8fafc; }
        .today-dialog-body { padding: 1rem 1.25rem 1.25rem; }
        .today-dialog-title { margin: 0 0 .2rem; font-weight: 800; }
        .today-dialog-caption { margin: 0; color: var(--muted, #64748b); }
        .today-close { position: absolute; top: .6rem; right: .6rem; width: 2.2rem; height: 2.2rem; border-radius: 50%; border: 0; background: rgba(15, 23, 42, .65); color: #fff; font-size: 1.2rem; line-height: 1; cursor: pointer; }
        @media (prefers-reduced-motion: reduce) { .today-frame { transition: none; } .today-tile:hover .today-frame { transform: none; } }
    </style>

    <section class="today-card shadow-sm mb-4" aria-labelledby="today-title" data-stories>
        <div class="today-head">
            <h2 id="today-title" class="today-title">Today at Rehab+</h2>
            <p class="today-sub">Schedules and moments from the clinic today.</p>
        </div>

        <div class="today-row">
            @foreach ($stories as $i => $story)
                <button type="button" class="today-tile" data-story-open="{{ $i }}" aria-label="Open {{ $story['title'] }}">
                    <span class="today-frame"><img src="{{ $story['image'] }}" alt="" loading="lazy"></span>
                    <span class="today-name">{{ $story['title'] }}</span>
                </button>
            @endforeach
        </div>

        <dialog class="today-dialog" data-story-dialog aria-labelledby="today-dialog-title">
            <div class="today-dialog-wrap">
                <form method="dialog"><button class="today-close" aria-label="Close">&times;</button></form>
                <img src="" alt="" data-story-image>
                <div class="today-dialog-body">
                    <p class="today-dialog-title" id="today-dialog-title" data-story-title></p>
                    <p class="today-dialog-caption" data-story-caption></p>
                </div>
            </div>
        </dialog>
    </section>

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

            root.querySelectorAll('[data-story-open]').forEach(function (button) {
                button.addEventListener('click', function () {
                    var story = stories[Number(button.getAttribute('data-story-open'))];
                    if (!story) return;
                    image.src = story.image;
                    image.alt = story.title;
                    title.textContent = story.title;
                    caption.textContent = story.caption || '';
                    dialog.showModal();
                });
            });

            // A click on the backdrop (outside the picture) closes the viewer.
            dialog.addEventListener('click', function (event) {
                if (event.target === dialog) dialog.close();
            });
        })();
    </script>
@endif
