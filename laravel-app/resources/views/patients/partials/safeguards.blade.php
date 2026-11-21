{{--
    Clinical safeguards on the patient page (API_CONTRACT.md "Clinical safeguards"):
    the clinician-validated clinical & dietary profile, the tolerance review flag,
    and program completion & physician clearance.

    Three states are labelled separately and never merged:
      Exercise completion            - the gate (ClearanceGate), from prescriptions + sessions
      Compliance                     - form accuracy & adherence, how well/regularly they exercised
      Medical clearance              - only a physician's signed clearances record
    Copy rule: never say "recovered"; say "cleared" only for a signed cleared record.
--}}
@use('App\Services\Patient\ClearanceGate')
@use('App\Services\Patient\ClearanceService')
@use('App\Services\Patient\ClinicalProfileService')
@use('App\Services\Patient\ExerciseCatalog')
@php
    $profileState = $clinicalProfile['status'];
    $profile = $clinicalProfile['profile'];
    $latestClearance = $clearances['records'][0] ?? null;
    $gateReady = $gate !== null && $gate['state'] === ClearanceGate::READY_FOR_REVIEW;
    $clearanceFields = ['decision', 'physician_name', 'physician_license', 'assessed_at', 'findings', 'recommendations', 'attested'];
    $oldDecision = old('decision', $gateReady ? '' : ClearanceService::NOT_CLEARED);
@endphp

{{-- Clinical & dietary profile --}}
<div class="card shadow-sm border-0 mb-4" id="clinical-profile">
    <div class="card-header d-flex justify-content-between align-items-center flex-wrap gap-2">
        <h5 class="mb-0">Clinical &amp; dietary profile</h5>
        @if ($canManage && $profileState === ClinicalProfileService::OK)
            <a href="{{ route('clinical-profile.edit', $patient['uid']) }}" class="btn btn-sm btn-outline-primary"><i class="bi bi-pencil me-1"></i>{{ $profile['exists'] ? 'Edit profile' : 'Add profile' }}</a>
        @endif
    </div>
    <div class="card-body">
        <p class="safeguard-note mb-3"><i class="bi bi-info-circle me-1"></i>Dietary information is context only; it never changes the exercise program. Only the clinician's restrictions and tolerance flag do.</p>

        @if ($profileState !== ClinicalProfileService::OK)
            <p class="safeguard-warning mb-0" data-clinical-profile="unavailable"><i class="bi bi-exclamation-circle me-1"></i>Clinical profile unavailable. Reload the page to try again.</p>
        @elseif (! $profile['exists'])
            <p class="text-muted mb-0" data-clinical-profile="none">No clinical profile recorded yet. Without one, no exercise is restricted and no tolerance caution is shown in the app.</p>
        @else
            <div class="row g-3" data-clinical-profile="ok">
                <div class="col-md-6">
                    <p class="fw-semibold mb-1">Medical precautions</p>
                    <p class="mb-0" style="white-space: pre-wrap;">{{ $profile['precautions'] ?: 'None recorded.' }}</p>
                </div>
                <div class="col-md-6">
                    <p class="fw-semibold mb-1">Restricted exercises</p>
                    @forelse ($profile['restrictedExercises'] as $code)
                        <span class="safeguard-badge safeguard-badge-danger me-1 mb-1"><i class="bi bi-slash-circle me-1"></i>{{ ExerciseCatalog::name($code) }}</span>
                    @empty
                        <p class="mb-0 text-muted">None.</p>
                    @endforelse
                </div>
                <div class="col-md-6">
                    <p class="fw-semibold mb-1">Exercise tolerance</p>
                    @if ($profile['lowTolerance'])
                        <span class="safeguard-badge safeguard-badge-warning"><i class="bi bi-exclamation-triangle me-1"></i>Low tolerance</span>
                    @else
                        <p class="mb-0 text-muted">Not flagged as low.</p>
                    @endif
                    @if ($profile['toleranceNote'] !== '')
                        <p class="mb-0 mt-1" style="white-space: pre-wrap;">{{ $profile['toleranceNote'] }}</p>
                    @endif
                </div>
                <div class="col-md-6">
                    <p class="fw-semibold mb-1">Nutrition flags <span class="text-muted fw-normal small">(context only)</span></p>
                    @forelse ($profile['nutritionFlags'] as $code)
                        <span class="safeguard-badge me-1 mb-1">{{ $nutritionFlagLabels[$code] ?? $code }}</span>
                    @empty
                        <p class="mb-0 text-muted">None.</p>
                    @endforelse
                </div>
                <div class="col-12">
                    <p class="fw-semibold mb-1">Dietary notes <span class="text-muted fw-normal small">(context only)</span></p>
                    <p class="mb-0" style="white-space: pre-wrap;">{{ $profile['dietaryNotes'] ?: 'None recorded.' }}</p>
                </div>
                <div class="col-12">
                    <p class="safeguard-meta mb-0">
                        Validated by {{ $profile['validatedByName'] ?: 'a clinician' }}
                        on {{ $profile['validatedAt']?->setTimezone($tz)->format('M j, Y') ?? 'an unknown date' }}
                        · Next reassessment: {{ $profile['nextReassessmentAt']?->setTimezone($tz)->format('M j, Y') ?? 'not planned' }}
                    </p>
                </div>
            </div>
        @endif

        {{-- Tolerance review flag: computed from the last 14 days of sessions, never stored --}}
        @if ($toleranceFlags !== [])
            <div class="safeguard-review mt-3" data-tolerance-review="flagged">
                <p class="fw-semibold mb-1"><i class="bi bi-flag-fill me-1"></i>Needs clinician review</p>
                <p class="safeguard-meta mb-2">
                    @if ($profile['lowTolerance'] || $profile['nutritionFlags'] !== [])
                        Sessions in the last {{ ClinicalProfileService::REVIEW_DAYS }} days with pain {{ ClinicalProfileService::REVIEW_PAIN_SENSITIVE }}/10 or higher, or ended early (this patient has a low tolerance or nutrition flag).
                    @else
                        Sessions in the last {{ ClinicalProfileService::REVIEW_DAYS }} days with pain {{ ClinicalProfileService::REVIEW_PAIN_ANYONE }}/10 or higher.
                    @endif
                    Reassess by editing the clinical profile and/or the exercises.
                </p>
                <ul class="mb-0 ps-3">
                    @foreach (array_slice($toleranceFlags, 0, 20) as $s)
                        <li>
                            {{ $s['startTime']->setTimezone($tz)->format('M j, g:i A') }} · {{ $s['exerciseName'] }}
                            · pain {{ $s['painLevel'] ?? '—' }}/10
                            @if ($s['endedEarly']) · ended early @endif
                        </li>
                    @endforeach
                </ul>
            </div>
        @endif
    </div>
</div>

{{-- Program completion & clearance --}}
<div class="card shadow-sm border-0 mb-4" id="clearance">
    <div class="card-header"><h5 class="mb-0">Program completion &amp; clearance</h5></div>
    <div class="card-body">
        <div class="row g-3 mb-3">
            {{-- 1. Exercise completion (the gate) --}}
            <div class="col-lg-4">
                <div class="safeguard-panel h-100" data-gate="{{ $gate['state'] ?? 'unavailable' }}">
                    <p class="safeguard-label mb-1">Exercise completion</p>
                    @if ($gate === null)
                        <p class="safeguard-warning mb-0"><i class="bi bi-exclamation-circle me-1"></i>Completion status unavailable. Reload the page to try again.</p>
                    @elseif ($gate['state'] === ClearanceGate::NO_PROGRAM)
                        <p class="fw-semibold mb-1">No program</p>
                        <p class="safeguard-meta mb-0">No active exercises are assigned, so there is nothing to complete.</p>
                    @elseif ($gate['state'] === ClearanceGate::IN_PROGRESS)
                        <p class="fw-semibold mb-1">In progress</p>
                        <p class="safeguard-meta mb-1">Still needed before a physician can record clearance:</p>
                        <ul class="mb-0 ps-3 small">
                            @foreach ($gate['missing'] as $missing)
                                <li>{{ ClearanceGate::describe($missing) }}</li>
                            @endforeach
                        </ul>
                    @else
                        <p class="fw-semibold mb-1 safeguard-ok"><i class="bi bi-check-circle me-1"></i>All prescribed exercises complete</p>
                        <p class="safeguard-meta mb-0">
                            @if (($latestClearance['decision'] ?? null) === ClearanceService::CLEARED)
                                A physician has signed a clearance (see Medical clearance).
                            @else
                                Ready for physician assessment.
                            @endif
                        </p>
                    @endif
                </div>
            </div>

            {{-- 2. Compliance: how well and how regularly, not a medical result --}}
            <div class="col-lg-4">
                <div class="safeguard-panel h-100">
                    <p class="safeguard-label mb-1">Compliance (form accuracy &amp; adherence)</p>
                    <p class="mb-1">Form accuracy: <strong>{{ $stats['total'] ? $stats['accuracy'].'%' : '—' }}</strong></p>
                    <p class="mb-1">Adherence this week: <strong>{{ $adherence['overall'] === null ? '—' : $adherence['overall'].'%' }}</strong></p>
                    <p class="safeguard-meta mb-0">How well and how regularly the patient exercised. An input for the physician, not a medical result.</p>
                </div>
            </div>

            {{-- 3. Medical clearance: only a signed physician decision --}}
            <div class="col-lg-4">
                <div class="safeguard-panel h-100" data-clearance="{{ $clearances['status'] === ClearanceService::OK ? ($latestClearance['decision'] ?? 'none') : 'unavailable' }}">
                    <p class="safeguard-label mb-1">Medical clearance (physician decision)</p>
                    @if ($clearances['status'] !== ClearanceService::OK)
                        <p class="safeguard-warning mb-0"><i class="bi bi-exclamation-circle me-1"></i>Clearance records unavailable. Reload the page to try again.</p>
                    @elseif ($latestClearance === null)
                        <p class="fw-semibold mb-1">No physician decision yet</p>
                        <p class="safeguard-meta mb-0">Clearance is only ever recorded by a physician's sign-off below; it is never automatic.</p>
                    @elseif ($latestClearance['decision'] === ClearanceService::CLEARED)
                        <p class="fw-semibold mb-1 safeguard-ok"><i class="bi bi-patch-check me-1"></i>Cleared by {{ $latestClearance['physicianName'] }}</p>
                        <p class="safeguard-meta mb-0">Assessed {{ $latestClearance['assessedAt']?->setTimezone($tz)->format('M j, Y') ?? '—' }} · PRC license {{ $latestClearance['physicianLicense'] }}</p>
                    @else
                        <p class="fw-semibold mb-1">Not cleared: continue / revise the program</p>
                        <p class="safeguard-meta mb-0">{{ $latestClearance['physicianName'] }}, assessed {{ $latestClearance['assessedAt']?->setTimezone($tz)->format('M j, Y') ?? '—' }}</p>
                    @endif
                </div>
            </div>
        </div>

        {{-- Clearance history (append-only, newest first) --}}
        @if ($clearances['status'] === ClearanceService::OK && $clearances['records'] !== [])
            <p class="fw-semibold mb-2">Clearance history</p>
            <div class="table-responsive mb-3">
                <table class="table mb-0 align-middle">
                    <thead class="table-light"><tr><th>Signed</th><th>Decision</th><th>Physician</th><th>Findings &amp; recommendations</th><th>Program at signing</th></tr></thead>
                    <tbody>
                        @foreach ($clearances['records'] as $record)
                            <tr>
                                <td class="small text-nowrap">{{ $record['signedAt']?->setTimezone($tz)->format('M j, Y g:i A') ?? '—' }}
                                    <div class="text-muted">by {{ $record['signedByName'] ?: '—' }}</div></td>
                                <td>
                                    @if ($record['decision'] === ClearanceService::CLEARED)
                                        <span class="badge bg-success">Cleared</span>
                                    @else
                                        <span class="badge bg-secondary">Not cleared</span>
                                    @endif
                                </td>
                                <td class="small">{{ $record['physicianName'] }}
                                    <div class="text-muted">PRC {{ $record['physicianLicense'] }} · assessed {{ $record['assessedAt']?->setTimezone($tz)->format('M j, Y') ?? '—' }}</div></td>
                                <td class="small">
                                    <div style="white-space: pre-wrap;">{{ $record['findings'] }}</div>
                                    @if ($record['recommendations'] !== '')<div class="text-muted mt-1" style="white-space: pre-wrap;">{{ $record['recommendations'] }}</div>@endif
                                </td>
                                <td class="small">
                                    {{ $record['programComplete'] ? 'Complete' : 'Incomplete' }}
                                    @foreach ($record['requirements'] as $req)
                                        <div class="text-muted">{{ $req['exerciseName'] }}: {{ $req['finished'] }}/{{ $req['required'] ?? '—' }}</div>
                                    @endforeach
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif

        {{-- Physician sign-off: admin or the patient's therapist --}}
        @if ($canManage)
            <form method="POST" action="{{ route('clearances.store', $patient['uid']) }}" class="safeguard-signoff" data-confirm="Record this physician decision for {{ $patient['name'] }}? It is permanent and can't be edited or deleted.">
                @csrf
                <p class="fw-semibold mb-1">Record physician decision</p>
                <p class="safeguard-meta mb-3">Records are permanent and can't be edited or deleted; a later record replaces the current status.</p>

                @if (collect($clearanceFields)->contains(fn ($f) => $errors->has($f)))
                    <div class="alert alert-danger">
                        <ul class="mb-0 ps-3">
                            @foreach ($clearanceFields as $field)
                                @foreach ($errors->get($field) as $message)
                                    <li>{{ $message }}</li>
                                @endforeach
                            @endforeach
                        </ul>
                    </div>
                @endif

                <div class="row g-3">
                    <div class="col-12">
                        <span class="form-label small fw-semibold d-block">Decision</span>
                        <div class="form-check">
                            <input class="form-check-input" type="radio" name="decision" value="{{ ClearanceService::CLEARED }}" id="decision_cleared" @checked($oldDecision === ClearanceService::CLEARED) @disabled(! $gateReady)>
                            <label class="form-check-label" for="decision_cleared">Cleared</label>
                            @if (! $gateReady)
                                <div class="form-text">Available once every prescribed exercise is complete (see Exercise completion).</div>
                            @endif
                        </div>
                        <div class="form-check">
                            <input class="form-check-input" type="radio" name="decision" value="{{ ClearanceService::NOT_CLEARED }}" id="decision_not_cleared" @checked($oldDecision === ClearanceService::NOT_CLEARED)>
                            <label class="form-check-label" for="decision_not_cleared">Not cleared (continue / revise the program)</label>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <label for="physician_name" class="form-label small fw-semibold">Physician name</label>
                        <input id="physician_name" type="text" name="physician_name" class="form-control" maxlength="100" value="{{ old('physician_name') }}" required>
                    </div>
                    <div class="col-md-3">
                        <label for="physician_license" class="form-label small fw-semibold">PRC license no.</label>
                        <input id="physician_license" type="text" name="physician_license" class="form-control" maxlength="40" value="{{ old('physician_license') }}" required>
                    </div>
                    <div class="col-md-3">
                        <label for="assessed_at" class="form-label small fw-semibold">Assessment date</label>
                        <input id="assessed_at" type="date" name="assessed_at" class="form-control" min="{{ $clearanceDates['min'] }}" max="{{ $clearanceDates['max'] }}" value="{{ old('assessed_at', $clearanceDates['max']) }}" required>
                    </div>
                    <div class="col-12">
                        <label for="findings" class="form-label small fw-semibold">Assessment findings</label>
                        <textarea id="findings" name="findings" class="form-control" rows="3" maxlength="2000" required>{{ old('findings') }}</textarea>
                    </div>
                    <div class="col-12">
                        <label for="recommendations" class="form-label small fw-semibold">Recommendations <span class="text-muted fw-normal">(optional)</span></label>
                        <textarea id="recommendations" name="recommendations" class="form-control" rows="2" maxlength="1000">{{ old('recommendations') }}</textarea>
                    </div>
                    <div class="col-12">
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" name="attested" value="1" id="attested" @checked(old('attested')) required>
                            <label class="form-check-label" for="attested">I confirm a physician performed a final assessment of this patient</label>
                        </div>
                    </div>
                    <div class="col-12 d-flex justify-content-end">
                        <button type="submit" class="btn btn-primary px-4">Record decision</button>
                    </div>
                </div>
            </form>
        @endif
    </div>
</div>
