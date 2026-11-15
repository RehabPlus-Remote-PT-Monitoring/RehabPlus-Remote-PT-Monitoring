{{--
    "Review exercise intensity" notice, shown on the patient page above the
    assigned exercises and on the assign/edit exercise form whenever the
    clinician marked the patient as low exercise tolerance (clinical
    profile). The panel asked that low tolerance flags a professional review
    of intensity, not only after a bad session. Expects $intensityProfile:
    a presented clinical profile with lowTolerance true.
--}}
<div class="safeguard-review mb-3" data-intensity-review="flagged" role="note">
    <p class="fw-semibold mb-1"><i class="bi bi-flag-fill me-1"></i>Low exercise tolerance: review the exercise intensity</p>
    <p class="mb-1 small">Check the reps or holds, hold length and sessions per week of every exercise for this patient before assigning or changing one. Lower them if needed.</p>
    @if ($intensityProfile['toleranceNote'] !== '')
        <p class="mb-1 small">Clinician's note: {{ $intensityProfile['toleranceNote'] }}</p>
    @endif
    @if ($intensityProfile['validatedByName'] !== '')
        <p class="mb-0 small safeguard-meta">Flagged by {{ $intensityProfile['validatedByName'] }}{{ $intensityProfile['validatedAt'] ? ' on '.$intensityProfile['validatedAt']->setTimezone(config('app.timezone'))->format('M j, Y') : '' }}</p>
    @endif
</div>
