{{-- The home hero: a full-width banner photo with the clinic name and calls to action. Needs $clinic (config/clinic.php). --}}
<section class="home-hero">
    <img src="{{ asset('assets/images/pt.jpg') }}" alt="" class="home-hero-bg">
    <div class="home-hero-shade" aria-hidden="true"></div>

    <div class="home-hero-content">
        <img src="{{ asset('assets/images/rehab-logo.jpg') }}" alt="{{ $clinic['name'] }} logo" class="home-hero-logo">
        <p class="home-hero-eyebrow">{{ $clinic['subtitle'] }}</p>
        <h1 class="home-hero-title">{{ $clinic['name'] }}</h1>

        <div class="home-hero-actions">
            <a href="{{ $clinic['facebook'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-primary">
                <i class="bi bi-facebook me-2"></i>Visit our Facebook page
            </a>
            <a href="{{ $clinic['instagram'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-outline-light">
                <i class="bi bi-instagram me-2"></i>Follow us on Instagram
            </a>
        </div>
    </div>
</section>
