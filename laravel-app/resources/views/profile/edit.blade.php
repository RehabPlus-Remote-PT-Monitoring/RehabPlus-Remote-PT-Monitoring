@extends('layouts.admin')

@section('title', 'My Profile')

@section('content')
    @php($initial = strtoupper(mb_substr($user['name'] ?: '?', 0, 1)))
    <div class="mb-3">
        <p class="page-title mb-1">My Profile</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ route('profile.update') }}" enctype="multipart/form-data" class="card shadow-sm border-0" style="max-width: 800px;">
        @csrf
        @method('PUT')

        <div class="card-body p-4">
            <div class="d-flex flex-column flex-sm-row align-items-sm-center gap-4 mb-4">
                {{-- Shows the chosen picture as soon as it is picked, before saving. --}}
                <img @if ($user['photoUrl'] !== '') src="{{ $user['photoUrl'] }}" @endif alt="" class="home-staff-photo flex-shrink-0" data-photo-preview @if ($user['photoUrl'] === '') hidden @endif>
                <div class="home-staff-initials flex-shrink-0" aria-hidden="true" data-photo-initials @if ($user['photoUrl'] !== '') hidden @endif>{{ $initial }}</div>
                <div class="flex-grow-1">
                    <label for="photo" class="form-label small fw-semibold">Profile picture</label>
                    <input id="photo" type="file" name="photo" accept="image/jpeg,image/png,image/webp" data-photo-input class="form-control @error('photo') is-invalid @enderror">
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
                    @if ($user['role'] === 'admin')
                        <select id="role" name="role" class="form-select" data-role-change data-current="admin" data-current-label="Administrator" data-name="{{ $user['name'] }}" data-self="1">
                            <option value="" disabled selected>Current: Administrator</option>
                            @foreach (\App\Auth\StaffUser::ROLE_LABELS as $value => $label)
                                @if ($value !== 'admin')
                                    <option value="{{ $value }}">{{ $label }}</option>
                                @endif
                            @endforeach
                        </select>
                        <div class="form-text">Changing your role changes what you can access. You will be asked to confirm.</div>
                    @else
                        <input type="text" class="form-control" value="{{ \App\Auth\StaffUser::ROLE_LABELS[$user['role']] ?? $user['role'] }}" disabled>
                        <div class="form-text">Only an administrator can change a role.</div>
                    @endif
                </div>
                <div class="col-md-6">
                    <label class="form-label small fw-semibold">Login email</label>
                    <input type="text" class="form-control" value="{{ $user['email'] }}" disabled>
                    <div class="form-text">Ask an administrator if this needs to change.</div>
                </div>

                <div class="col-12">
                    <hr class="my-2">
                    <p class="small fw-semibold mb-1">Personal contact details</p>
                    <p class="form-text mt-0">Shown on the team section of the website. Your login email is used only to sign in.</p>
                </div>
                @php($contact = \App\Helpers\PhoneNumber::parse($user['contactPhone'] ?? ''))
                @include('partials.phone-field', ['field' => 'phone', 'label' => 'Personal contact number', 'country' => old('phone_country', $contact['iso']), 'number' => old('phone', $contact['national']), 'initial' => old('phone', $contact['national']), 'required' => false])
                <div class="col-md-6">
                    <label for="contact_email" class="form-label small fw-semibold">Personal contact email</label>
                    <input id="contact_email" type="email" name="contact_email" class="form-control @error('contact_email') is-invalid @enderror" value="{{ old('contact_email', $user['contactEmail']) }}" placeholder="name@gmail.com" maxlength="150">
                    @error('contact_email')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">A personal email, such as Gmail.</div>
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4">Save changes</button>
        </div>
    </form>
@endsection
