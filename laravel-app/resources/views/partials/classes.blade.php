{{-- The clinic's classes, with a photo for each. Needs $clinic['classes'] from config/clinic.php. --}}
<h2 class="section-title">Classes</h2>

<div class="row g-4 mb-4">
    @foreach ($clinic['classes'] as $class)
        <div class="col-12 col-md-6 col-xl-4">
            <article class="card shadow-sm border-0 h-100 overflow-hidden class-card">
                <div class="class-card-photo">
                    <img src="{{ asset($class['image']) }}" alt="{{ $class['title'] }}" loading="lazy">
                </div>

                <div class="class-card-body">
                    <h3 class="class-card-title">{{ $class['title'] }}</h3>

                    <div class="class-card-meta">
                        <span><i class="bi bi-clock"></i>{{ $class['duration'] }}</span>
                        <span><i class="bi bi-bar-chart-steps"></i>{{ $class['level'] }}</span>
                    </div>

                    <p class="class-card-text mb-0">{{ $class['description'] }}</p>
                </div>
            </article>
        </div>
    @endforeach
</div>
