@extends('layouts.admin')

@section('title', 'Post Announcement')

@section('content')
    <div class="mb-3">
        <a href="{{ route('dashboard') }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>Back to dashboard</a>
        <p class="page-title mb-1 mt-1">Announcements</p>
        <p class="page-subtitle mb-0">Post news for the team and visitors. Announcements show on the dashboard and on the clinic's welcome page.</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ route('announcements.store') }}" enctype="multipart/form-data" class="card shadow-sm border-0 mb-4" style="max-width: 800px;">
        @csrf

        <div class="card-body p-4">
            <div class="row g-3">
                <div class="col-12">
                    <label for="title" class="form-label small fw-semibold">Title</label>
                    <input id="title" type="text" name="title" class="form-control @error('title') is-invalid @enderror" value="{{ old('title') }}" required minlength="3" maxlength="120" placeholder="e.g. Clinic closed on November 1 and 2">
                    @error('title')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-12">
                    <label for="body" class="form-label small fw-semibold">Message</label>
                    <textarea id="body" name="body" rows="4" class="form-control @error('body') is-invalid @enderror" required minlength="3" maxlength="1000" placeholder="The details patients and staff need to know.">{{ old('body') }}</textarea>
                    @error('body')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">Up to 1,000 characters.</div>
                </div>

                <div class="col-md-6">
                    <label for="image" class="form-label small fw-semibold">Picture (optional)</label>
                    <input id="image" type="file" name="image" accept="image/jpeg,image/png,image/webp" class="form-control @error('image') is-invalid @enderror">
                    @error('image')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">JPG, PNG or WebP, up to 2 MB. Large pictures are resized automatically.</div>
                </div>

                <div class="col-md-6">
                    <label for="show_until" class="form-label small fw-semibold">Show until (optional)</label>
                    <input id="show_until" type="date" name="show_until" class="form-control @error('show_until') is-invalid @enderror" value="{{ old('show_until') }}" min="{{ now()->toDateString() }}">
                    @error('show_until')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">Leave empty to keep it up until it is removed.</div>
                </div>
            </div>
        </div>

        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4"><i class="bi bi-megaphone me-1"></i>Post announcement</button>
        </div>
    </form>

    <h2 class="section-title">Currently showing</h2>
    @if ($announcements === [])
        <div class="card shadow-sm border-0 text-center text-muted py-5 mb-4">No announcements yet.</div>
    @else
        <div class="row g-3 mb-4">
            @foreach ($announcements as $announcement)
                @if ($announcement['archived'] && ($loop->first || ! $announcements[$loop->index - 1]['archived']))
                    <div class="col-12 small fw-semibold text-muted text-uppercase mt-2">Archived</div>
                @endif
                <div class="col-12">
                    <div @class([
                        'card shadow-sm border-0 p-3 d-flex flex-row flex-wrap align-items-start gap-3',
                        'announcement-archived' => $announcement['archived'],
                    ])>
                        @if ($announcement['imageUrl'] !== '')
                            <img src="{{ $announcement['imageUrl'] }}" alt="" class="announcement-thumb">
                        @endif
                        <div class="flex-grow-1 min-w-0">
                            <p class="announcement-title mb-1">
                                {{ $announcement['title'] }}
                                @if ($announcement['archived'])
                                    <span class="badge bg-secondary ms-1 align-middle">Archived</span>
                                @endif
                            </p>
                            <p class="small text-muted mb-1">
                                @if ($announcement['postedAt'])
                                    {{ $announcement['postedAt']->setTimezone(config('app.timezone'))->format('M j, Y') }} ·
                                @endif
                                {{ $announcement['postedByName'] ?: 'Staff' }}
                                @if ($announcement['showUntil'])
                                    · Until {{ \Carbon\CarbonImmutable::parse($announcement['showUntil'])->format('M j, Y') }}
                                @endif
                            </p>
                            <p class="announcement-body mb-0">{{ $announcement['body'] }}</p>
                        </div>
                        <div class="d-flex gap-2 flex-shrink-0">
                            @if ($announcement['archived'])
                                <form method="POST" action="{{ route('announcements.restore', $announcement['id']) }}" data-confirm="Restore this announcement? It will show on the dashboard and the welcome page again.">
                                    @csrf
                                    <button type="submit" class="btn btn-sm btn-outline-success"><i class="bi bi-arrow-counterclockwise me-1"></i>Restore</button>
                                </form>
                            @else
                                <form method="POST" action="{{ route('announcements.archive', $announcement['id']) }}" data-confirm="Archive this announcement? It will no longer show on the welcome page. You can restore it later.">
                                    @csrf
                                    <button type="submit" class="btn btn-sm btn-outline-secondary"><i class="bi bi-archive me-1"></i>Archive</button>
                                </form>
                            @endif
                            <form method="POST" action="{{ route('announcements.destroy', $announcement['id']) }}" data-confirm="Delete this announcement permanently? This can't be undone." data-confirm-danger>
                                @csrf
                                @method('DELETE')
                                <button type="submit" class="btn btn-sm btn-outline-danger"><i class="bi bi-trash me-1"></i>Delete</button>
                            </form>
                        </div>
                    </div>
                </div>
            @endforeach
        </div>
    @endif
@endsection
