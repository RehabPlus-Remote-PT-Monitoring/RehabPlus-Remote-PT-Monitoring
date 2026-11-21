{{-- The price lists (images) for pilates and rehab packages. Needs $clinic['packages'] from config/clinic.php. --}}
<h2 class="section-title">Packages</h2>
<div class="row g-3 mb-4">
    @foreach ($clinic['packages'] as $package)
        <div class="col-12 col-lg-6">
            <div class="card shadow-sm border-0 h-100 p-3">
                <h3 class="package-title">{{ $package['title'] }}</h3>
                <a href="{{ asset($package['image']) }}" target="_blank" rel="noopener noreferrer" class="d-block" title="Open the full price list">
                    <img src="{{ asset($package['image']) }}" alt="{{ $package['title'] }} price list" class="package-image" loading="lazy">
                </a>
            </div>
        </div>
    @endforeach
</div>
