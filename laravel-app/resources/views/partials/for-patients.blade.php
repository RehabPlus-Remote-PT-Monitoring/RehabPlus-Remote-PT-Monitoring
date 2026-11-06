{{-- RehabPlus Remote Monitoring: the prescription-only patient app, and how patient accounts are created. Needs $clinic. --}}
<section id="patients" class="patient-band mb-4" aria-labelledby="patients-heading">
    @include('partials.band-decor')
    <div class="patient-band-text">
        <p class="patient-band-eyebrow">Exclusive patient access</p>
        <h2 id="patients-heading" class="patient-band-title">RehabPlus Remote Monitoring App</h2>
        <p class="patient-band-body">
            The RehabPlus Mobile App is a prescription-only tool, provided exclusively to official patients of
            {{ $clinic['name'] }} who are currently enrolled in a rehabilitation package.
        </p>
        <p class="patient-band-body mt-3">
            It is an alternative way to continue your rehabilitation for patients who have a hard time keeping to clinic
            schedules or who live far from the clinic.
        </p>
        <p class="patient-band-body mt-3">
            Our exclusive mobile platform uses AI-powered real-time pose estimation to guide our patients through
            prescribed home exercises, ensuring proper form and allowing our licensed physical therapists to monitor
            recovery progress remotely.
        </p>
    </div>

    <div class="patient-band-points">
        <div class="patient-band-point"><i class="bi bi-check-circle-fill"></i><span>Prescribed by your therapist</span></div>
        <div class="patient-band-point"><i class="bi bi-check-circle-fill"></i><span>For enrolled patients only</span></div>
        <div class="patient-band-point"><i class="bi bi-check-circle-fill"></i><span>Not available for public download</span></div>
        <p class="patient-band-note">
            <i class="bi bi-info-circle me-1"></i>There is no public registration. Patient accounts are created only by
            clinic staff, after a face-to-face clinical assessment.
        </p>
        <a href="{{ route('remote-monitoring') }}" class="patient-band-btn">
            Learn more <i class="bi bi-arrow-right ms-1" aria-hidden="true"></i>
        </a>
    </div>

    <div class="patient-band-gallery" role="group" aria-label="Screens from the RehabPlus Mobile App">
        <img src="{{ asset('assets/images/app/app-login.jpg') }}" alt="RehabPlus Mobile App sign-in screen" class="app-shot" loading="lazy">
        <img src="{{ asset('assets/images/app/app-home.jpg') }}" alt="RehabPlus Mobile App home screen" class="app-shot app-shot-center" loading="lazy">
        <img src="{{ asset('assets/images/app/app-exercises.jpg') }}" alt="RehabPlus Mobile App exercise list" class="app-shot" loading="lazy">
    </div>
</section>
