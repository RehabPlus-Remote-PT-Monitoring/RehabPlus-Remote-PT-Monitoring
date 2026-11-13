{{-- The team, grouped by role. Needs $staff from StaffDirectory::board(). --}}
<h3 class="team-heading">Our team</h3>
@if ($staff === [])
    <div class="card shadow-sm border-0 text-center text-muted py-5 mb-4">No staff accounts yet.</div>
@else
    @foreach ($staff as $group)
        <div class="team-group mb-4" data-team="{{ \Illuminate\Support\Str::slug($group['role']) }}">
            <div class="team-group-head">
                <h3 class="team-group-title">{{ $group['role'] }}</h3>
            </div>

            <div class="row g-3">
                @foreach ($group['members'] as $member)
                    <div class="col-12 col-sm-6 col-lg-4">
                        <article class="team-card">
                            @if ($member['photoUrl'] !== '')
                                <img src="{{ $member['photoUrl'] }}" alt="{{ $member['name'] }}" class="team-card-photo" loading="lazy">
                            @else
                                <div class="team-card-initials" aria-hidden="true">{{ strtoupper(mb_substr($member['name'] ?: '?', 0, 1)) }}</div>
                            @endif

                            <h4 class="team-card-name">{{ $member['name'] }}</h4>

                            @if ($member['phone'] !== '' || $member['email'] !== '')
                                <ul class="team-card-contact">
                                    @if ($member['phone'] !== '')
                                        <li><i class="bi bi-telephone" aria-hidden="true"></i><span>{{ $member['phone'] }}</span></li>
                                    @endif
                                    @if ($member['email'] !== '')
                                        <li>
                                            <i class="bi bi-envelope" aria-hidden="true"></i>
                                            <a href="https://mail.google.com/mail/?view=cm&amp;fs=1&amp;to={{ rawurlencode($member['email']) }}" target="_blank" rel="noopener noreferrer">{{ $member['email'] }}</a>
                                        </li>
                                    @endif
                                </ul>
                            @endif
                        </article>
                    </div>
                @endforeach
            </div>
        </div>
    @endforeach
@endif
