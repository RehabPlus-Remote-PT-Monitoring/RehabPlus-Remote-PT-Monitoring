@extends('layouts.admin')

@section('title', $patient ? 'Edit Patient' : 'Add Patient')

@section('content')
    @php($me = auth()->user())
    <div class="mb-3">
        <a href="{{ $patient ? route('patients.show', $patient['uid']) : route('patients.index') }}" class="text-decoration-none small">
            <i class="bi bi-arrow-left me-1"></i>{{ $patient ? 'Back to patient' : 'Back to patients' }}
        </a>
        <p class="page-title mb-1 mt-1">{{ $patient ? 'Edit '.$patient['name'] : 'Add Patient' }}</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ $patient ? route('patients.update', $patient['uid']) : route('patients.store') }}" class="card shadow-sm border-0" style="max-width: 900px;"
        @if ($patient) data-confirm-changes="Save these changes to {{ $patient['name'] }}'s profile?" @endif>
        @csrf
        @if ($patient)
            @method('PUT')
        @endif

        <div class="card-body p-4">
            <div class="row g-3">
                <div class="col-md-6">
                    <label for="name" class="form-label small fw-semibold">Full name</label>
                    <input id="name" type="text" name="name" class="form-control" @if ($patient) data-initial="{{ $patient['name'] ?? '' }}" @endif placeholder="Patient" value="{{ old('name', $patient['name'] ?? '') }}" required maxlength="100">
                </div>
                <div class="col-md-6">
                    <label for="condition" class="form-label small fw-semibold">Condition</label>
                    <input id="condition" type="text" name="condition" class="form-control" @if ($patient) data-initial="{{ $patient['condition'] ?? '' }}" @endif value="{{ old('condition', $patient['condition'] ?? '') }}" required maxlength="150" placeholder="e.g. MCL sprain, post-acute">
                </div>

                @if (! $patient)
                    <div class="col-12"><hr class="my-1"><p class="fw-semibold mb-0 mt-2">App login</p>
                        <p class="text-muted small mb-0">Click the icon to generate a temporary password, then give it to the patient with their email.</p></div>
                    <div class="col-md-6" data-email-wrap>
                        <label for="email" class="form-label small fw-semibold">Email</label>
                        <div class="input-group">
                            <input id="email" type="email" name="email" class="form-control @error('email') is-invalid @enderror" value="{{ old('email') }}" placeholder="patient@rehabplus.com" required maxlength="150" autocomplete="off" data-email-check="{{ route('email-check') }}">
                            <span class="input-group-text" data-email-status aria-hidden="true"></span>
                        </div>
                        <div class="form-text text-danger" data-email-feedback></div>
                        @error('email')
                            <div class="invalid-feedback d-block">{{ $message }}</div>
                        @enderror
                    </div>
                    <div class="col-md-6">
                        <label for="password" class="form-label small fw-semibold">Temporary password</label>
                        <div class="input-group">
                            <input id="password" type="text" name="password" class="form-control font-monospace @error('password') is-invalid @enderror" required minlength="{{ \App\Services\Firebase\FirebaseAdmin::MIN_PASSWORD }}" value="{{ old('password') }}" autocomplete="off" spellcheck="false" aria-describedby="password-hint" data-password-lock @unless (old('password')) readonly @endunless>
                            <button type="button" class="btn btn-outline-primary" data-generate-password="#password" data-email-field="#email" data-generate-url="{{ route('patients.temporary-password') }}" title="Generate a temporary password" aria-label="Generate a temporary password">
                                <i class="bi bi-arrow-repeat" aria-hidden="true"></i>
                            </button>
                            @error('password')
                                <div class="invalid-feedback">{{ $message }}</div>
                            @enderror
                        </div>
                        <div class="form-text" id="password-hint" data-password-hint>Enter the patient's email first, then click the button to generate a password.</div>
                    </div>
                    <div class="col-12"><hr class="my-1"></div>
                @else
                    <div class="col-md-6">
                        <label class="form-label small fw-semibold">App login email</label>
                        <input type="text" class="form-control" value="{{ $patient['email'] }}" disabled>
                    </div>
                @endif

                @php($phone = \App\Helpers\PhoneNumber::parse($patient['phone'] ?? ''))
                @php($phoneCountry = old('phone_country', $phone['iso']))
                @php($phoneNumber = old('phone', $phone['national']))
                @include('partials.phone-field', ['field' => 'phone', 'label' => 'Mobile number (for password reset texts)', 'country' => $phoneCountry, 'number' => $phoneNumber, 'initial' => $patient ? $phoneNumber : null, 'required' => false])
                <div class="col-md-6">
                    <label for="dob" class="form-label small fw-semibold">Date of birth</label>
                    <div class="input-group"><input id="dob" type="date" name="dob" class="form-control @error('dob') is-invalid @enderror" min="1900-01-01" max="{{ now()->toDateString() }}" data-calendar-only @if ($patient) data-initial="{{ $patient['birthDate'] ?? '' }}" @endif value="{{ old('dob', $patient['birthDate'] ?? '') }}"><button type="button" class="btn btn-primary field-picker-button" data-date-open aria-label="Open calendar" title="Open calendar"><i class="bi bi-calendar3" aria-hidden="true"></i></button></div>
                    @error('dob')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="gender" class="form-label small fw-semibold">Gender</label>
                    <select id="gender" name="gender" class="form-select @error('gender') is-invalid @enderror" @if ($patient) data-initial="{{ $patient['gender'] ?? '' }}" @endif>
                        <option value="">Not set</option>
                        @foreach (\App\Services\Patient\PatientService::GENDERS as $option)
                            <option value="{{ $option }}" @selected(old('gender', $patient['gender'] ?? '') === $option)>{{ $option }}</option>
                        @endforeach
                    </select>
                    @error('gender')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="weight_kg" class="form-label small fw-semibold">Weight (kg)</label>
                    <input id="weight_kg" type="number" name="weight_kg" class="form-control @error('weight_kg') is-invalid @enderror" min="{{ \App\Services\Patient\PatientService::MIN_WEIGHT_KG }}" max="{{ \App\Services\Patient\PatientService::MAX_WEIGHT_KG }}" step="any" inputmode="decimal" placeholder="e.g. 62.5" value="{{ old('weight_kg', $patient['weightKg'] ?? '') }}" @if ($patient) data-initial="{{ $patient['weightKg'] ?? '' }}" @endif>
                    @error('weight_kg')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="height_cm" class="form-label small fw-semibold">Height (cm)</label>
                    <input id="height_cm" type="number" name="height_cm" class="form-control @error('height_cm') is-invalid @enderror" min="{{ \App\Services\Patient\PatientService::MIN_HEIGHT_CM }}" max="{{ \App\Services\Patient\PatientService::MAX_HEIGHT_CM }}" step="any" inputmode="decimal" placeholder="e.g. 168" value="{{ old('height_cm', $patient['heightCm'] ?? '') }}" @if ($patient) data-initial="{{ $patient['heightCm'] ?? '' }}" @endif>
                    @error('height_cm')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-12">
                    <label for="address_street" class="form-label small fw-semibold">Street and house number</label>
                    <input id="address_street" type="text" name="address_street" class="form-control @error('address_street') is-invalid @enderror" maxlength="150" value="{{ old('address_street', $patient['addressStreet'] ?? '') }}" placeholder="e.g. Blk 2 Lot 5, 123 Rizal St.">
                    @error('address_street')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="address_barangay" class="form-label small fw-semibold">Barangay</label>
                    <input id="address_barangay" type="text" name="address_barangay" class="form-control @error('address_barangay') is-invalid @enderror" maxlength="100" value="{{ old('address_barangay', $patient['addressBarangay'] ?? '') }}">
                    @error('address_barangay')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="address_city" class="form-label small fw-semibold">City or municipality</label>
                    <input id="address_city" type="text" name="address_city" class="form-control @error('address_city') is-invalid @enderror" maxlength="100" value="{{ old('address_city', $patient['addressCity'] ?? '') }}">
                    @error('address_city')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-4">
                    <label for="address_province" class="form-label small fw-semibold">Province</label>
                    <input id="address_province" type="text" name="address_province" class="form-control @error('address_province') is-invalid @enderror" maxlength="100" value="{{ old('address_province', $patient['addressProvince'] ?? '') }}">
                    @error('address_province')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>

                @if ($me->isAdmin())
                    <div class="col-md-6">
                        <label for="therapist_id" class="form-label small fw-semibold">Assigned therapist</label>
                        <select id="therapist_id" name="therapist_id" class="form-select" @if ($patient) data-initial="{{ $patient['therapistId'] ?? '' }}" @endif>
                            <option value="">Unassigned</option>
                            @foreach ($therapists as $t)
                                <option value="{{ $t['uid'] }}" @selected(old('therapist_id', $patient['therapistId'] ?? '') === $t['uid'])>{{ $t['name'] }}</option>
                            @endforeach
                        </select>
                        @if (! $therapists)
                            <div class="form-text">No therapist accounts yet. Add one under Staff Accounts.</div>
                        @endif
                    </div>
                @elseif (! $patient)
                    <div class="col-md-6">
                        <label class="form-label small fw-semibold">Assigned therapist</label>
                        <input type="text" class="form-control" value="{{ $me->name }} (you)" disabled>
                    </div>
                @endif

                <div class="col-12">
                    <label for="medical_summary" class="form-label small fw-semibold">Medical summary</label>
                    <textarea id="medical_summary" name="medical_summary" class="form-control" @if ($patient) data-initial="{{ $patient['medicalSummary'] ?? '' }}" @endif rows="3" maxlength="2000">{{ old('medical_summary', $patient['medicalSummary'] ?? '') }}</textarea>
                </div>
                <div class="col-12">
                    <label for="therapy_plan" class="form-label small fw-semibold">Therapy plan</label>
                    <textarea id="therapy_plan" name="therapy_plan" class="form-control" @if ($patient) data-initial="{{ $patient['therapyPlan'] ?? '' }}" @endif rows="3" maxlength="2000">{{ old('therapy_plan', $patient['therapyPlan'] ?? '') }}</textarea>
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4">{{ $patient ? 'Save changes' : 'Create patient' }}</button>
        </div>
    </form>
@endsection
