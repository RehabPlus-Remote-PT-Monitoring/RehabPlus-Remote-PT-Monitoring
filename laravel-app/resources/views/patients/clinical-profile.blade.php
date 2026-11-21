@extends('layouts.admin')

@section('title', 'Clinical profile')

@section('content')
    @php
        $selectedFlags = old('nutrition_flags', $profile['nutritionFlags']);
        $selectedRestricted = old('restricted_exercises', $profile['restrictedExercises']);
        $selectedFlags = is_array($selectedFlags) ? $selectedFlags : [];
        $selectedRestricted = is_array($selectedRestricted) ? $selectedRestricted : [];
        $reassessment = old('next_reassessment_at', $profile['nextReassessmentAt']?->setTimezone(config('app.timezone'))->format('Y-m-d') ?? '');
    @endphp
    <div class="mb-3">
        <a href="{{ route('patients.show', $patient['uid']) }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>Back to {{ $patient['name'] }}</a>
        <p class="page-title mb-1 mt-1">Clinical &amp; dietary profile</p>
        <p class="page-subtitle mb-0">{{ $patient['name'] }}</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ route('clinical-profile.update', $patient['uid']) }}" class="card shadow-sm border-0" style="max-width: 900px;">
        @csrf
        @method('PUT')

        <div class="card-body p-4">
            <p class="safeguard-note mb-4"><i class="bi bi-info-circle me-1"></i>Dietary information is context only; it never changes the exercise program. Only the clinician's restrictions and tolerance flag do.</p>

            <div class="row g-3">
                <div class="col-12">
                    <label for="precautions" class="form-label small fw-semibold">Medical precautions</label>
                    <textarea id="precautions" name="precautions" class="form-control" rows="3" maxlength="{{ \App\Services\Patient\ClinicalProfileService::MAX_PRECAUTIONS }}" placeholder="Shown to the patient in the app, e.g. Avoid deep knee bends until the next review.">{{ old('precautions', $profile['precautions']) }}</textarea>
                </div>

                <div class="col-12">
                    <span class="form-label small fw-semibold d-block">Restricted exercises <span class="text-muted fw-normal">(contraindicated: the app locks them and they can't be assigned or resumed)</span></span>
                    <div class="safeguard-checks mt-1">
                        @foreach ($catalog as $code => [$name])
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" name="restricted_exercises[]" value="{{ $code }}" id="restricted_{{ $code }}" @checked(in_array($code, $selectedRestricted, true))>
                                <label class="form-check-label" for="restricted_{{ $code }}">{{ $name }}</label>
                            </div>
                        @endforeach
                    </div>
                </div>

                <div class="col-md-4">
                    <span class="form-label small fw-semibold d-block">Exercise tolerance</span>
                    <div class="form-check mt-1">
                        <input type="hidden" name="low_tolerance" value="0">
                        <input class="form-check-input" type="checkbox" name="low_tolerance" value="1" id="low_tolerance" @checked((bool) old('low_tolerance', $profile['lowTolerance']))>
                        <label class="form-check-label" for="low_tolerance">Low tolerance (the app shows a caution before each session)</label>
                    </div>
                </div>
                <div class="col-md-8">
                    <label for="tolerance_note" class="form-label small fw-semibold">Tolerance note</label>
                    <textarea id="tolerance_note" name="tolerance_note" class="form-control" rows="2" maxlength="{{ \App\Services\Patient\ClinicalProfileService::MAX_TOLERANCE_NOTE }}" placeholder="Why, and what to watch for.">{{ old('tolerance_note', $profile['toleranceNote']) }}</textarea>
                </div>

                <div class="col-12">
                    <span class="form-label small fw-semibold d-block">Nutrition flags <span class="text-muted fw-normal">(context only)</span></span>
                    <div class="safeguard-checks mt-1">
                        @foreach ($nutritionFlags as $code => $label)
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" name="nutrition_flags[]" value="{{ $code }}" id="flag_{{ $code }}" @checked(in_array($code, $selectedFlags, true))>
                                <label class="form-check-label" for="flag_{{ $code }}">{{ $label }}</label>
                            </div>
                        @endforeach
                    </div>
                </div>

                <div class="col-12">
                    <label for="dietary_notes" class="form-label small fw-semibold">Dietary notes <span class="text-muted fw-normal">(context only)</span></label>
                    <textarea id="dietary_notes" name="dietary_notes" class="form-control" rows="3" maxlength="{{ \App\Services\Patient\ClinicalProfileService::MAX_DIETARY_NOTES }}">{{ old('dietary_notes', $profile['dietaryNotes']) }}</textarea>
                </div>

                <div class="col-md-4">
                    <label for="next_reassessment_at" class="form-label small fw-semibold">Next reassessment <span class="text-muted fw-normal">(optional)</span></label>
                    <input id="next_reassessment_at" type="date" name="next_reassessment_at" class="form-control" min="{{ $reassessmentDates['min'] }}" max="{{ $reassessmentDates['max'] }}" value="{{ $reassessment }}">
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent d-flex justify-content-between align-items-center flex-wrap gap-2">
            <small class="text-muted">
                @if ($profile['validatedAt'])
                    Last validated by {{ $profile['validatedByName'] ?: 'a clinician' }} on {{ $profile['validatedAt']->setTimezone(config('app.timezone'))->format('M j, Y') }}. Saving records you as the validating clinician.
                @else
                    Saving records you as the validating clinician.
                @endif
            </small>
            <button type="submit" class="btn btn-primary px-4">Save profile</button>
        </div>
    </form>
@endsection
