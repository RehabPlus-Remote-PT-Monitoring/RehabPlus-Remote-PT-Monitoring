@extends('layouts.public')

@section('title', $title)

@section('content')
    <article class="info-page card shadow-sm border-0 p-4 p-lg-5 mx-auto">
        <a href="{{ route('landing') }}" class="back-link small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

        <h1 class="info-page-title">{{ $title }}</h1>
        <p class="info-page-subtitle">{{ config('clinic.copyright') }} Terms and Conditions</p>

        <p class="info-text">
            Welcome to the Rehab+ website ("Website") and the RehabPlus Remote Monitoring app ("App") of Rehab+ Physiotherapy
            and Pilates ("Rehab+"). By accessing or using the Website or the App, you agree to comply with and be bound by the
            following terms and conditions ("Terms"). Please read them carefully. If you do not agree to these Terms, you may
            not use the Website or the App.
        </p>

        <h2 class="info-section-title">1. Use of the Website and App</h2>
        <p class="info-text">
            The Website provides information about Rehab+, including our services, classes, packages, schedule, and contact
            details. You can also book appointments and classes through the Contact Us section of the Website.
        </p>
        <p class="info-text">
            The App is intended for patients of Rehab+ who have been prescribed it by their physiotherapist as part of a
            rehabilitation package.
        </p>
        <p class="info-text">
            You must be at least 13 years old to use the App. If you are under 18 years old, use of the App or our services
            must be with the consent of a parent or legal guardian.
        </p>

        <h2 class="info-section-title">2. Accounts and Access</h2>
        <p class="info-text">
            There is no public registration for the App. Access is set up by Rehab+ staff for patients who have been prescribed
            the App. You agree to provide accurate, current, and complete information when your account is set up.
        </p>
        <p class="info-text">
            You are responsible for maintaining the confidentiality of your login details and for all activities that occur
            under your account.
        </p>

        <h2 class="info-section-title">3. Services, Classes, and Appointments</h2>
        <p class="info-text">
            Rehab+ offers Rehabilitation, Physiotherapy, Clinical Pilates, Group Pilates, Private Sessions, and related
            movement-based services.
        </p>
        <p class="info-text">
            Appointments and class bookings are made through the Contact Us section of the Website, by phone, or in person. All appointments
            and class reservations are subject to availability and to our cancellation and refund policies, and to any studio
            guidelines communicated by Rehab+ staff.
        </p>

        <h2 class="info-section-title">4. Fees and Payments</h2>
        <p class="info-text">
            You agree to pay all applicable fees for sessions, classes, and packages at the rates in effect at the time of
            purchase. Payments are recorded by Rehab+ staff.
        </p>
        <p class="info-text">
            Rehab+ reserves the right to adjust its prices. Any changes will be communicated in advance and will take effect for
            purchases made after the change.
        </p>

        <h2 class="info-section-title">5. Packages and Validity</h2>
        <p class="info-text">
            Class packages have a validity period, and unused credits expire at the end of that period. The validity period,
            expiration, and refund rules are set out in our <a href="{{ route('info.show', 'refund-policy') }}">Refund Policy</a>.
        </p>

        <h2 class="info-section-title">6. Cancellation and Refund Policy</h2>
        <p class="info-text">
            Cancellations or rescheduling of appointments and classes must comply with our
            <a href="{{ route('info.show', 'cancellation-policy') }}">Class Cancellation &amp; Late Arrival Policy</a>, which may be
            updated periodically.
        </p>
        <p class="info-text">
            Late cancellations or no-shows may result in session forfeiture or applicable charges.
        </p>
        <p class="info-text">
            Refunds are processed strictly in accordance with our <a href="{{ route('info.show', 'refund-policy') }}">Refund Policy</a>.
        </p>

        <h2 class="info-section-title">7. Health, Medical Disclosure, and Safety</h2>
        <p class="info-text">By booking or participating in any Rehab+ services, you confirm that:</p>
        <ul class="info-list">
            <li>You have disclosed all relevant medical conditions, injuries, or limitations to your Physiotherapist or Instructor</li>
            <li>You are medically cleared to participate in rehabilitation or exercise-based activities</li>
            <li>
                You acknowledge that participation in physiotherapy, rehabilitation, and Pilates involves inherent risks. You
                agree to follow all instructions, safety guidelines, and professional advice provided by Rehab+ staff.
            </li>
        </ul>
        <p class="info-text">
            Rehab+ reserves the right to refuse or modify services if participation is deemed unsafe.
        </p>

        <h2 class="info-section-title">8. Professional Scope of Care</h2>
        <p class="info-text">
            Physiotherapy services are provided by licensed Physiotherapists within their professional scope of practice.
        </p>
        <p class="info-text">
            Pilates and movement sessions may be provided by licensed Physiotherapists or qualified instructors. These sessions
            are not a substitute for medical diagnosis unless explicitly stated as part of physiotherapy care.
        </p>

        <h2 class="info-section-title">9. Intellectual Property</h2>
        <p class="info-text">
            All content available through the Website and the App, including text, graphics, logos, videos, and software, is the
            property of Rehab+ or its licensors and is protected by intellectual property laws.
        </p>
        <p class="info-text">
            You may not copy, reproduce, distribute, or modify any content without prior written consent from Rehab+.
        </p>

        <h2 class="info-section-title">10. Privacy Policy</h2>
        <p class="info-text">
            Your use of the App is governed by the Privacy Policy you accept when you sign in to the App. By using the App, you
            consent to the collection and use of personal information in accordance with that policy.
        </p>

        <h2 class="info-section-title">11. Limitation of Liability</h2>
        <p class="info-text">
            To the fullest extent permitted by law, Rehab+ shall not be liable for any injury, loss, or damages arising from:
        </p>
        <ul class="info-list">
            <li>Use of the Website or the App</li>
            <li>Participation in physiotherapy, rehabilitation, or Pilates services</li>
            <li>Equipment use or facility access</li>
        </ul>
        <p class="info-text">Participation is voluntary and undertaken at your own risk.</p>

        <h2 class="info-section-title">12. Modification of Terms</h2>
        <p class="info-text">
            Rehab+ reserves the right to update or modify these Terms and Conditions at any time. Changes will be effective
            immediately upon posting on the Website.
        </p>
        <p class="info-text">
            Continued use of the Website or the App, or of our services, after updates constitutes acceptance of the revised Terms.
        </p>

        <h2 class="info-section-title">13. Governing Law</h2>
        <p class="info-text">
            These Terms and Conditions are governed by and construed in accordance with the laws of the applicable jurisdiction
            in which Rehab+ operates.
        </p>

        <h2 class="info-section-title">14. Contact Information</h2>
        <p class="info-text">
            For questions regarding these Terms and Conditions, please contact Rehab+ at
            <span class="fw-semibold">{{ $clinic['phone'] }}</span> or
            <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>.
        </p>

        <p class="info-text mb-0">
            By using the Website or the App, or receiving services from Rehab+, you acknowledge that you have read, understood,
            and agreed to be bound by these Terms and Conditions.
        </p>
    </article>
@endsection
