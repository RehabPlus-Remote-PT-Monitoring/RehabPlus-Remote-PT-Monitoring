{{-- Rewards and recognitions from config/clinic.php ('awards'). --}}
<h3 class="team-heading">Recognitions &amp; Rewards</h3>
@if ($clinic['awards'] === [])
    <div class="card shadow-sm border-0 text-center text-muted py-5 mb-4">No awards added yet.</div>
@else
    <div class="row g-3 mb-4">
        @foreach ($clinic['awards'] as $award)
            <div class="col-md-6 col-xl-4">
                <div class="card shadow-sm border-0 h-100 p-3 d-flex flex-row align-items-start gap-3">
                    <div class="home-icon"><i class="bi {{ $award['icon'] ?? 'bi-award-fill' }}"></i></div>
                    <div class="min-w-0">
                        <p class="fw-semibold mb-0">{{ $award['title'] }}</p>
                        @if (! empty($award['issuer']))
                            <p class="text-muted small mb-1">{{ $award['issuer'] }}</p>
                        @endif
                        @if (! empty($award['year']))
                            <span class="badge bg-success-subtle text-success">{{ $award['year'] }}</span>
                        @endif
                    </div>
                </div>
            </div>
        @endforeach
    </div>
@endif
