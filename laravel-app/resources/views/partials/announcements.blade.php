{{-- Clinic announcements, newest first. Needs $announcements from AnnouncementService::current(). --}}
@if ($announcements !== [])
    <section id="announcements" class="announcements mb-4" aria-labelledby="announcements-heading">
        <h2 id="announcements-heading" class="section-title">Announcements</h2>

        @foreach ($announcements as $announcement)
            <article class="card shadow-sm border-0 overflow-hidden announcement-card mb-3">
                <div class="row g-0">
                    @if ($announcement['imageUrl'] !== '')
                        <div class="col-12 col-md-5">
                            <img src="{{ $announcement['imageUrl'] }}" alt="{{ $announcement['title'] }}" class="announcement-image" loading="lazy">
                        </div>
                    @endif

                    <div @class(['col-12', 'col-md-7' => $announcement['imageUrl'] !== ''])>
                        <div class="announcement-text">
                            <svg class="announcement-watermark" viewBox="0 0 80 80" aria-hidden="true" focusable="false">
                                <circle cx="40" cy="32" r="22" fill="currentColor"/>
                                <rect x="30" y="50" width="20" height="14" rx="4" fill="currentColor"/>
                                <rect x="33" y="66" width="14" height="6" rx="3" fill="currentColor"/>
                                <path d="M40 2 V8 M12 14 L16 18 M68 14 L64 18 M2 36 H8 M78 36 H72" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
                            </svg>
                            <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
                                <span class="announcement-badge"><i class="bi bi-lightbulb-fill me-1"></i>Announcement</span>
                                @if ($announcement['postedAt'])
                                    <span class="small text-muted">{{ $announcement['postedAt']->setTimezone(config('app.timezone'))->format('F j, Y') }}</span>
                                @endif
                            </div>

                            <h3 class="announcement-title">{{ $announcement['title'] }}</h3>
                            <p class="announcement-body">{{ $announcement['body'] }}</p>

                            @if ($announcement['postedByName'] !== '')
                                <p class="small text-muted mb-0">Posted by {{ $announcement['postedByName'] }}</p>
                            @endif
                        </div>
                    </div>
                </div>
            </article>
        @endforeach
    </section>
@endif
