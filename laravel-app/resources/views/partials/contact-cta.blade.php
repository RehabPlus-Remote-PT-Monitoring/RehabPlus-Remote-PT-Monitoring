{{-- Ways to reach the clinic, and where to follow for updates. Never register or sign in on this website. Needs $clinic. --}}
<section id="contact" class="card shadow-sm border-0 p-4 p-lg-5 text-center mb-4" aria-labelledby="contact-heading">
    <h2 id="contact-heading" class="fw-bold mb-2">Have a question?</h2>
    <p class="text-muted mb-4">Contact us on Facebook or Instagram, or send us an email. And follow us there for more updates.</p>

    <div class="d-flex flex-wrap justify-content-center gap-2 mb-4">
        <a href="{{ $clinic['facebook'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-primary btn-lg px-4">
            <i class="bi bi-facebook me-2"></i>Contact Us on Facebook
        </a>
        <a href="{{ $clinic['instagram'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-outline-primary btn-lg px-4">
            <i class="bi bi-instagram me-2"></i>Contact Us on Instagram
        </a>
    </div>

    <p class="small text-muted mb-0">
        Or call <span class="fw-semibold text-body">{{ $clinic['phone'] }}</span> or email
        <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>.
    </p>
</section>
