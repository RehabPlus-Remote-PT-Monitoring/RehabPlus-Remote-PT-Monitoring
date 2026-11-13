{{-- Schedule, location, contact and email. Needs $clinic (config/clinic.php). --}}
<section class="card shadow-sm border-0 home-info mb-4">
    <div class="row g-0">
        <div class="col-12 col-md-6 col-xl-3 home-info-item">
            <div class="home-icon"><i class="bi bi-clock"></i></div>
            <div>
                <p class="home-label">Schedule</p>
                @foreach ($clinic['schedule'] as $slot)
                    <p class="home-value">{{ $slot['days'] }}<span>{{ $slot['hours'] }}</span></p>
                @endforeach
            </div>
        </div>
        <div class="col-12 col-md-6 col-xl-3 home-info-item">
            <div class="home-icon"><i class="bi bi-geo-alt"></i></div>
            <div>
                <p class="home-label">Location</p>
                <a href="{{ $clinic['map_url'] }}" target="_blank" rel="noopener noreferrer" class="home-value">{{ $clinic['location'] }}</a>            </div>
        </div>
        <div class="col-12 col-md-6 col-xl-3 home-info-item">
            <div class="home-icon"><i class="bi bi-telephone"></i></div>
            <div>
                <p class="home-label">Contact</p>
                <p class="home-value">{{ $clinic['phone'] }}</p>
            </div>
        </div>
        <div class="col-12 col-md-6 col-xl-3 home-info-item">
            <div class="home-icon"><i class="bi bi-envelope"></i></div>
            <div class="min-w-0">
                <p class="home-label">Email</p>
                <a href="https://mail.google.com/mail/?view=cm&amp;fs=1&amp;to={{ rawurlencode($clinic['email']) }}" class="home-value" target="_blank" rel="noopener noreferrer">{{ $clinic['email'] }}</a>
            </div>
        </div>
    </div>
</section>
