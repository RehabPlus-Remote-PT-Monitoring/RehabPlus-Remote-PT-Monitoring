@extends('layouts.admin')

@section('title', $user ? 'Edit Account' : 'New Staff Account')

@section('content')
    @php
        $me = auth()->user();
        $roleLocked = $user && ($user['role'] === 'therapist' || $user['uid'] === $me->id);
        $selectedRole = old('role', $user['role'] ?? 'therapist');
        $contact = \App\Helpers\PhoneNumber::parse($user['contactPhone'] ?? '');
        $contactCountry = old('phone_country', $contact['iso']);
        $contactNumber = old('phone', $contact['national']);
    @endphp
    <div class="mb-3">
        <a href="{{ route('users.index') }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>Back to staff accounts</a>
        <p class="page-title mb-1 mt-1">{{ $user ? 'Edit '.$user['name'] : 'New Staff Account' }}</p>
        <p class="page-subtitle mb-0">{{ $user ? $user['email'] : 'Creates a login for the clinic dashboard.' }}</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ $user ? route('users.update', $user['uid']) : route('users.store') }}" class="card shadow-sm border-0" style="max-width: 800px;">
        @csrf
        @if ($user)
            @method('PUT')
        @endif

        <div class="card-body p-4">
            <div class="row g-3">
                <div class="col-md-6">
                    <label for="name" class="form-label small fw-semibold">Full name</label>
                    <input id="name" type="text" name="name" class="form-control" value="{{ old('name', $user['name'] ?? '') }}" required maxlength="100" @unless ($user) placeholder="{{ \App\Auth\StaffUser::ROLE_LABELS[$selectedRole] ?? '' }}" @endunless>
                    @if ($user && $user['role'] === 'therapist')
                        <div class="form-text">Their patients see this name in the app.</div>
                    @endif
                </div>
                <div class="col-md-6">
                    <label for="role" class="form-label small fw-semibold">Role</label>
                    @if ($roleLocked)
                        <input type="text" class="form-control" value="{{ \App\Auth\StaffUser::ROLE_LABELS[$user['role']] }} (locked)" disabled>
                        <div class="form-text">{{ $user['role'] === 'therapist' ? 'Therapist accounts keep their role because patients are assigned to them.' : 'You can\'t change your own role.' }}</div>
                    @else
                        <select id="role" name="role" class="form-select" @unless ($user) data-role-defaults @endunless>
                            @foreach (\App\Auth\StaffUser::ROLE_LABELS as $value => $label)
                                <option value="{{ $value }}" data-name="{{ $label }}" data-email="{{ $value }}@rehabplus.com" @selected($selectedRole === $value)>{{ $label }}</option>
                            @endforeach
                        </select>
                        <div class="form-text">Physical therapists manage their own patients. Administrators can do everything, including managing staff accounts.</div>
                    @endif
                </div>

                @unless ($user)
                    <div class="col-md-6" data-email-wrap>
                        <label for="email" class="form-label small fw-semibold">Email</label>
                        <div class="input-group">
                            <input id="email" type="email" name="email" class="form-control @error('email') is-invalid @enderror" value="{{ old('email') }}" placeholder="{{ $selectedRole }}@rehabplus.com" required maxlength="150" autocomplete="off" data-email-check="{{ route('email-check') }}">
                            <span class="input-group-text" data-email-status aria-hidden="true"></span>
                        </div>
                        <div class="form-text text-danger" data-email-feedback></div>
                        @error('email')
                            <div class="invalid-feedback d-block">{{ $message }}</div>
                        @enderror
                    </div>
                @endunless
                <div class="col-md-6">
                    <label for="password" class="form-label small fw-semibold">{{ $user ? 'New password (optional)' : 'Password' }}</label>
                    <input id="password" type="password" name="password" class="form-control" minlength="{{ \App\Services\Firebase\FirebaseAdmin::MIN_PASSWORD }}" @required(! $user) @unless ($user) placeholder="**********" @endunless autocomplete="new-password">
                </div>

                <div class="col-12">
                    <hr class="my-2">
                    <p class="small fw-semibold mb-1">Personal contact details</p>
                    <p class="form-text mt-0">Shown on the team section of the website. The login email above is used only to sign in.</p>
                </div>
                @include('partials.phone-field', ['field' => 'phone', 'label' => 'Personal contact number', 'country' => $contactCountry, 'number' => $contactNumber, 'initial' => $user ? $contactNumber : null, 'required' => false])
                <div class="col-md-6">
                    <label for="contact_email" class="form-label small fw-semibold">Personal contact email</label>
                    <input id="contact_email" type="email" name="contact_email" class="form-control @error('contact_email') is-invalid @enderror" value="{{ old('contact_email', $user['contactEmail'] ?? '') }}" placeholder="name@gmail.com" maxlength="150">
                    @error('contact_email')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                    <div class="form-text">A personal email, such as Gmail.</div>
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4">{{ $user ? 'Save changes' : 'Create account' }}</button>
        </div>
    </form>
@endsection
