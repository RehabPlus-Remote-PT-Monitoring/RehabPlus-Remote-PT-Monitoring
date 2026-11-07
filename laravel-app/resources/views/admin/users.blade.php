@extends('layouts.admin')

@section('title', $showArchived ? 'Archived Staff' : 'Staff Accounts')

@section('content')
    @php($me = auth()->user())
    <div class="d-flex flex-wrap justify-content-between align-items-start gap-3 mb-4">
        <div>
            <p class="page-title mb-1">{{ $showArchived ? 'Archived Staff' : 'Staff Accounts' }}</p>
        </div>
        <div class="d-flex flex-wrap gap-2">
            @if ($showArchived)
                <a href="{{ route('users.index') }}" class="btn btn-outline-secondary">
                    <i class="bi bi-arrow-left me-1"></i>Back to current staff
                </a>
            @else
                <a href="{{ route('users.index', ['archived' => 1]) }}" class="btn btn-outline-secondary">
                    <i class="bi bi-archive me-1"></i>Archived Staff
                    @if ($archivedCount > 0)<span class="badge bg-secondary ms-1">{{ $archivedCount }}</span>@endif
                </a>
                <a href="{{ route('users.create') }}" class="btn btn-primary">
                    <i class="bi bi-person-plus-fill me-2"></i>Add Staff Account
                </a>
            @endif
        </div>
    </div>

    @include('partials.flash')

    @unless ($showArchived)
        <div class="row g-4 mb-4">
            @foreach ([
                ['Staff accounts', count($users), 'bi-person-badge-fill', 'text-success'],
                ['Therapists', count(array_filter($users, fn ($u) => $u['role'] === 'therapist' && $u['active'])), 'bi-heart-pulse-fill', 'text-info'],
                ['Patient app accounts', $patientCount, 'bi-people-fill', 'text-primary'],
            ] as [$label, $value, $icon, $tone])
                <div class="col-md-4"><div class="card stat-card h-100 border-0"><div class="d-flex justify-content-between align-items-center"><div><div class="stat-label">{{ $label }}</div><h4 class="stat-value mb-0">{{ $value }}</h4></div><i class="bi {{ $icon }} {{ $tone }} fs-3"></i></div></div></div>
            @endforeach
        </div>
    @endunless

    <div id="staff-roles" class="card border-0 shadow-sm overflow-hidden">
        <div class="table-responsive">
            <table class="table align-middle mb-0">
                <thead class="table-light">
                    <tr>
                        <th class="px-4">Account</th>
                        <th>Email</th>
                        <th>Role</th>
                        <th>Status</th>
                        @if ($showArchived)<th>Archived</th>@endif
                        <th class="text-end pe-4">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($users as $user)
                        <tr class="{{ $user['active'] ? '' : 'opacity-75' }}">
                            <td class="px-4 py-3">
                                <div class="d-flex align-items-center gap-3">
                                    @if ($user['photoUrl'] !== '')
                                        <img src="{{ $user['photoUrl'] }}" alt="" class="rounded-circle flex-shrink-0" style="width:44px;height:44px;object-fit:cover;">
                                    @else
                                        <div class="rounded-circle text-white fw-bold d-flex align-items-center justify-content-center" style="width:44px;height:44px;background:linear-gradient(135deg,#14b8a6,#06b6d4);">{{ strtoupper(mb_substr($user['name'], 0, 1)) }}</div>
                                    @endif
                                    <div class="fw-bold">{{ $user['name'] }}@if ($user['uid'] === $me->id) <span class="text-muted fw-normal small">(you)</span>@endif</div>
                                </div>
                            </td>
                            <td>{{ $user['email'] }}</td>
                            <td>
                                @php($badge = ['admin' => 'bg-danger', 'therapist' => 'bg-info text-dark'][$user['role']] ?? 'bg-light text-dark')
                                <span class="badge {{ $badge }} rounded-pill px-3 py-2">{{ \App\Auth\StaffUser::ROLE_LABELS[$user['role']] ?? ucfirst($user['role']) }}</span>
                            </td>
                            <td>
                                @if (in_array($user['uid'], $noLogin, true))
                                    <span class="badge bg-warning text-dark" title="This account's login was deleted. Delete the leftover record here.">No login</span>
                                @elseif ($user['archived'])
                                    <span class="badge bg-secondary">Archived</span>
                                @else
                                    {!! $user['active'] ? '<span class="badge bg-success">Active</span>' : '<span class="badge bg-secondary">Disabled</span>' !!}
                                @endif
                            </td>
                            @if ($showArchived)
                                <td class="text-muted small">
                                    {{ $user['archivedAt']?->setTimezone(config('app.timezone'))->format('M j, Y') ?? '—' }}
                                    @if ($user['archivedByName'] !== '')
                                        <div>by {{ $user['archivedByName'] }}</div>
                                    @endif
                                </td>
                            @endif
                            <td class="text-end pe-4 text-nowrap">
                                <a href="{{ route('users.edit', $user['uid']) }}" class="btn btn-sm btn-outline-primary">Edit</a>
                                @if ($user['uid'] !== $me->id)
                                    @if ($showArchived)
                                        <form method="POST" action="{{ route('users.restore', $user['uid']) }}" class="d-inline ms-1" data-confirm="Restore {{ $user['name'] }}? They return to the staff list and can sign in again.">
                                            @csrf
                                            <button type="submit" class="btn btn-sm btn-outline-success"><i class="bi bi-arrow-counterclockwise me-1"></i>Restore</button>
                                        </form>
                                        <form method="POST" action="{{ route('users.destroy', $user['uid']) }}" class="d-inline ms-1" data-confirm="Delete {{ $user['name'] }} permanently? Their login and staff record are removed. This can't be undone." data-confirm-danger>
                                            @csrf
                                            @method('DELETE')
                                            <button type="submit" class="btn btn-sm btn-outline-danger"><i class="bi bi-trash me-1"></i>Delete permanently</button>
                                        </form>
                                    @elseif (in_array($user['uid'], $noLogin, true))
                                        <form method="POST" action="{{ route('users.destroy', $user['uid']) }}" class="d-inline ms-1" data-confirm="Delete this leftover record? The account has no login anymore." data-confirm-danger>
                                            @csrf
                                            @method('DELETE')
                                            <button type="submit" class="btn btn-sm btn-outline-danger"><i class="bi bi-trash me-1"></i>Delete record</button>
                                        </form>
                                    @else
                                        <form method="POST" action="{{ route('users.status', $user['uid']) }}" class="d-inline ms-1" @if ($user['active']) data-confirm="Disable this account? They will no longer be able to sign in." @endif>
                                            @csrf
                                            <input type="hidden" name="active" value="{{ $user['active'] ? 0 : 1 }}">
                                            <button class="btn btn-sm {{ $user['active'] ? 'btn-outline-secondary' : 'btn-outline-success' }}">{{ $user['active'] ? 'Disable' : 'Enable' }}</button>
                                        </form>
                                        <form method="POST" action="{{ route('users.archive', $user['uid']) }}" class="d-inline ms-1" data-confirm="Archive {{ $user['name'] }}? They can no longer sign in and leave the staff list. You can restore them from Archived Staff." data-confirm-danger>
                                            @csrf
                                            <button type="submit" class="btn btn-sm btn-outline-danger"><i class="bi bi-archive me-1"></i>Archive</button>
                                        </form>
                                    @endif
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="{{ $showArchived ? 6 : 5 }}" class="text-center text-muted py-4">{{ $showArchived ? 'No archived staff.' : 'No staff accounts yet.' }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
@endsection
