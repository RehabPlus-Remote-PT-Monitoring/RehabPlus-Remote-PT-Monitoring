{{--
    Patient profile header: the picture, identity, actions, and the details in boxes.
    Expects $patient, $avatarUrl, $consent, $canMessage, $isAdmin, $tz from patients/show.
--}}
<div class="mb-3">
    <a href="{{ route('patients.index') }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>All patients</a>
</div>

<div class="card shadow-sm border-0 mb-4" data-patient-profile>
    <div class="card-body p-4">
        {{-- Picture, name and the actions, side by side --}}
        <div class="d-flex flex-column flex-md-row align-items-md-center gap-4">
            <img src="{{ $avatarUrl }}" alt="Profile picture of {{ $patient['name'] }}" width="120" height="120" class="rounded-circle border flex-shrink-0" style="object-fit: cover; background: #fff;" data-patient-avatar>

            <div class="flex-grow-1">
                <div class="d-flex justify-content-between align-items-start flex-wrap gap-3">
                    <div>
                        <p class="page-title mb-1">
                            {{ $patient['name'] }}
                            @if ($patient['archived'])
                                <span class="badge bg-secondary align-middle ms-2" style="font-size:.8rem;">Archived</span>
                            @endif
                        </p>
                        <p class="page-subtitle mb-1">{{ $patient['condition'] }}</p>
                        <p class="small text-muted mb-0"><strong>Therapist:</strong> {{ $patient['therapistName'] ?: 'Unassigned' }}</p>
                    </div>
                    <div class="d-flex flex-wrap gap-2" data-patient-actions>
                        @if ($canMessage && ! $patient['archived'])
                            <a href="{{ route('messages.show', $patient['uid']) }}" class="btn btn-outline-primary"><i class="bi bi-chat-dots me-1"></i>Message</a>
                        @endif
                        @if ($isAdmin)
                            <a href="{{ route('patients.edit', $patient['uid']) }}" class="btn btn-outline-secondary"><i class="bi bi-pencil me-1"></i>Edit</a>
                            @if ($patient['archived'])
                                <form method="POST" action="{{ route('patients.restore', $patient['uid']) }}" data-confirm="Restore {{ $patient['name'] }}? Their app login is enabled again and they show up in the patient list.">@csrf
                                    <button class="btn btn-outline-success"><i class="bi bi-arrow-counterclockwise me-1"></i>Restore</button>
                                </form>
                            @else
                                <form method="POST" action="{{ route('patients.password', $patient['uid']) }}" data-confirm="Reset the app password for {{ $patient['name'] }}? Make sure it is really the patient contacting you. Their current password stops working straight away.">@csrf
                                    <button class="btn btn-outline-primary"><i class="bi bi-key me-1"></i>Reset password</button>
                                </form>
                                <form method="POST" action="{{ route('patients.archive', $patient['uid']) }}" data-confirm="Archive {{ $patient['name'] }}? Their app login is disabled; their records are kept and you can restore them later." data-confirm-danger>@csrf
                                    <button class="btn btn-outline-danger"><i class="bi bi-archive me-1"></i>Archive</button>
                                </form>
                            @endif
                        @endif
                    </div>
                </div>
            </div>
        </div>

        {{-- The details, each in its own box across the full width --}}
        <div class="row g-3 mt-3">
            <div class="col-md-4">
                <div class="border rounded-3 p-3 h-100">
                    <p class="small text-uppercase text-muted fw-semibold mb-2">Contact</p>
                    <p class="mb-1"><i class="bi bi-envelope me-2 text-muted"></i>{{ $patient['email'] ?: '—' }}</p>
                    <p class="mb-1"><i class="bi bi-telephone me-2 text-muted"></i>{{ $patient['phone'] ?: '—' }}</p>
                    <p class="mb-0"><i class="bi bi-geo-alt me-2 text-muted"></i>{{ $patient['address'] ?: 'No address recorded' }}</p>
                </div>
            </div>

            <div class="col-md-4">
                <div class="border rounded-3 p-3 h-100">
                    <p class="small text-uppercase text-muted fw-semibold mb-2">Personal</p>
                    <p class="mb-1"><i class="bi bi-calendar3 me-2 text-muted" title="Date of birth" aria-label="Date of birth"></i>{{ $patient['dob'] ?: '—' }}@if ($patient['age'] !== null) <span class="text-muted">({{ $patient['age'] }} years old)</span>@endif</p>
                    <p class="mb-1"><i class="bi bi-person me-2 text-muted" title="Gender" aria-label="Gender"></i><span class="text-muted">Gender:</span> {{ $patient['gender'] ?: 'Not set' }}</p>
                    <p class="mb-1"><i class="bi bi-speedometer2 me-2 text-muted" title="Weight" aria-label="Weight"></i><span class="text-muted">Weight:</span> {{ $patient['weightKg'] !== null ? $patient['weightKg'].' kg' : 'Not set' }}</p>
                    <p class="mb-1"><i class="bi bi-rulers me-2 text-muted" title="Height" aria-label="Height"></i><span class="text-muted">Height:</span> {{ $patient['heightCm'] !== null ? $patient['heightCm'].' cm' : 'Not set' }}</p>
                    <p class="mb-0"><i class="bi bi-calendar-plus me-2 text-muted" title="Added" aria-label="Added"></i>Added {{ $patient['createdAt']?->setTimezone($tz)->format('M j, Y') ?? '—' }}</p>
                </div>
            </div>

            {{-- Terms / Privacy Policy consent the patient gave in the app (read-only, see ConsentService) --}}
            <div class="col-md-4">
                <div class="border rounded-3 p-3 h-100">
                    <p class="small text-uppercase text-muted fw-semibold mb-2">Terms and consent</p>
                    <p class="consent-status mb-0" data-consent="{{ $consent['status'] }}">
                        @switch($consent['status'])
                            @case(\App\Services\Patient\ConsentService::CURRENT)
                            @case(\App\Services\Patient\ConsentService::OUTDATED)
                                <i class="bi bi-shield-check me-1"></i>Accepted terms v{{ $consent['version'] }}
                                on {{ $consent['acceptedAt']?->setTimezone($tz)->format('M j, Y') ?? 'an unknown date' }}
                                @foreach ($consent['flags'] as $flagLabel => $flagGiven)
                                    <span class="consent-flag {{ $flagGiven ? '' : 'consent-flag-missing' }} ms-2" title="{{ $flagLabel }}: {{ $flagGiven ? 'agreed' : 'not agreed' }}"><i class="bi {{ $flagGiven ? 'bi-check-lg' : 'bi-x-lg' }}"></i>{{ $flagLabel }}</span>
                                @endforeach
                                @if ($consent['status'] === \App\Services\Patient\ConsentService::OUTDATED)
                                    <span class="consent-outdated d-block mt-1"><i class="bi bi-exclamation-circle me-1"></i>This is an older version (current is v{{ $consent['currentVersion'] }}). The patient will be asked to accept the new terms next time they open the app.</span>
                                @endif
                                @break
                            @case(\App\Services\Patient\ConsentService::NONE)
                                <i class="bi bi-shield me-1"></i>Not yet accepted (the patient hasn't signed in to the app yet)
                                @break
                            @default
                                <i class="bi bi-shield-exclamation me-1"></i>Consent status unavailable. Reload the page to try again.
                        @endswitch
                    </p>
                </div>
            </div>
        </div>
    </div>
</div>

@include('partials.flash')

@include('patients.temporary-password')
