@extends('layouts.admin')

@section('title', 'My Profile')

@section('content')
    @php($initial = strtoupper(mb_substr($user['name'] ?: '?', 0, 1)))
    <div class="mb-3">
        <p class="page-title mb-1">My Profile</p>
        <p class="page-subtitle mb-0">Your name and picture show on the Home page staff board.</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ route('profile.update') }}" enctype="multipart/form-data" class="card shadow-sm border-0" style="max-width: 800px;">
        @csrf
        @method('PUT')

        <div class="card-body p-4">
            <div class="d-flex flex-column flex-sm-row align-items-sm-center gap-4 mb-4">
                @if ($user['photoUrl'] !== '')
                    <img src="{{ $user['photoUrl'] }}" alt="" class="home-staff-photo flex-shrink-0">
                @else
                    <div class="home-staff-initials flex-shrink-0" aria-hidden="true">{{ $initial }}</div>
                @endif
                <div class="flex-grow-1">
                    <label for="photo" class="form-label small fw-semibold">Profile picture</label>
                    <input id="photo" type="file" name="photo" accept="image/jpeg,image/png,image/webp" class="form-control @error('photo') is-invalid @enderror">
                    @error('photo')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">JPG, PNG or WebP, up to 500 KB.</div>
                    @if ($user['photoUrl'] !== '')
                        <div class="form-check mt-2">
                            <input class="form-check-input" type="checkbox" name="remove_photo" value="1" id="remove_photo">
                            <label class="form-check-label small" for="remove_photo">Remove my picture</label>
                        </div>
                    @endif
                </div>
            </div>

            <div class="row g-3">
                <div class="col-md-6">
                    <label for="name" class="form-label small fw-semibold">Full name</label>
                    <input id="name" type="text" name="name" class="form-control @error('name') is-invalid @enderror" value="{{ old('name', $user['name']) }}" required maxlength="100">
                    @error('name')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label class="form-label small fw-semibold">Role</label>
                    <input type="text" class="form-control" value="{{ \App\Auth\StaffUser::ROLE_LABELS[$user['role']] ?? $user['role'] }}" disabled>
                    <div class="form-text">Only an administrator can change a role, on Staff Accounts.</div>
                </div>
                <div class="col-md-6">
                    <label class="form-label small fw-semibold">Login email</label>
                    <input type="text" class="form-control" value="{{ $user['email'] }}" disabled>
                    <div class="form-text">Ask an administrator if this needs to change.</div>
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4">Save changes</button>
        </div>
    </form>
@endsection
