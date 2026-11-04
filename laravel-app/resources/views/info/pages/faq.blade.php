@extends('layouts.public')

@section('title', $title)

@section('content')
    <article class="info-page card shadow-sm border-0 p-4 p-lg-5 mx-auto">
        <a href="{{ route('landing') }}" class="back-link small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

        <h1 class="info-page-title">{{ $title }}</h1>
        <p class="info-page-subtitle">{{ config('clinic.copyright') }}: Frequently Asked Questions</p>

        <h2 class="info-section-title">Getting started</h2>

        <details class="faq-item">
            <summary>What should I bring to my first visit?</summary>
            <p class="info-text">
                Bring a valid ID, any medical records related to your concern, and imaging results such as X-rays or MRIs if
                you have them. It also helps to bring a list of your current medications and any allergies. Wear comfortable,
                athletic-type clothing, since you may be asked to move and exercise during your visit.
            </p>
        </details>

        <details class="faq-item">
            <summary>How long is a session?</summary>
            <p class="info-text">
                Pilates classes are 50 minutes, except Pilatherapy, which is 120 minutes. Physiotherapy session length depends
                on your assessment and treatment plan, and your therapist will confirm it when you book.
            </p>
        </details>

        <details class="faq-item">
            <summary>How many sessions will I need?</summary>
            <p class="info-text">
                It depends on your condition, your medical history, and how severe your symptoms are. Your physiotherapist
                will assess you at your first visit and recommend a plan, including the number of visits. Your progress is
                reviewed as treatment continues.
            </p>
        </details>

        <details class="faq-item">
            <summary>What should I wear for class?</summary>
            <p class="info-text">
                Wear comfortable, stretchy clothing that lets you move freely. For reformer sessions, grip socks help you stay
                steady on the equipment.
            </p>
        </details>

        <h2 class="info-section-title">Pilates and classes</h2>

        <details class="faq-item">
            <summary>What is the difference between Clinical Pilates and general fitness Pilates?</summary>
            <p class="info-text">
                Clinical Pilates focuses on rehabilitation and movement quality. Exercises are adjusted to your injuries,
                conditions, and goals, and progress is tracked over time. General fitness Pilates is usually a group workout
                focused on overall strength and conditioning. Both can be useful; the right choice depends on where you are in
                your recovery or training.
            </p>
        </details>

        <details class="faq-item">
            <summary>I am a beginner. Which class should I take?</summary>
            <p class="info-text">
                Start with <strong>Essentials</strong>, our beginner class, which covers the foundations of Pilates. Once you
                are comfortable, <strong>Flow &amp; Lengthen</strong> is our intermediate class. <strong>Jumpboard Flow Class</strong>
                and <strong>Strong &amp; Centered</strong> are advanced. <strong>Clinical Pilates (Private)</strong>,
                <strong>Private Duo</strong>, and <strong>Pilatherapy</strong> are open to all levels.
            </p>
        </details>

        <details class="faq-item">
            <summary>Do I need a physiotherapy assessment before joining a class?</summary>
            <p class="info-text">
                If you have an injury, an ongoing condition, or recent surgery, we recommend speaking with a physiotherapist
                before joining a group class. This helps us recommend the right class and make sure the exercises are safe for
                you.
            </p>
        </details>

        <details class="faq-item">
            <summary>Do I need to disclose my medical history?</summary>
            <p class="info-text">
                Yes. Before you take part in any service, please tell your physiotherapist or instructor about any relevant
                medical conditions, injuries, or limitations. This is part of our safety process and is described in our
                <a href="{{ route('info.show', 'terms') }}">Terms &amp; Conditions</a>.
            </p>
        </details>

        <h2 class="info-section-title">Booking and policies</h2>

        <details class="faq-item">
            <summary>How do I book a session or class?</summary>
            <p class="info-text">
                Booking is done through our Contact Us section. Contact us on <a href="{{ config('clinic.facebook') }}" target="_blank" rel="noopener noreferrer">Facebook</a>
                or <a href="{{ config('clinic.instagram') }}" target="_blank" rel="noopener noreferrer">Instagram</a>, send us
                an email at <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>, or call
                <span class="fw-semibold">{{ $clinic['phone'] }}</span>.
            </p>
        </details>

        <details class="faq-item">
            <summary>What are your clinic hours?</summary>
            <p class="info-text">
                @foreach ($clinic['schedule'] as $row)
                    {{ $row['days'] }}: {{ $row['hours'] }}@if (! $loop->last)<br>@endif
                @endforeach
            </p>
        </details>

        <details class="faq-item">
            <summary>What is your cancellation policy?</summary>
            <p class="info-text">
                Class cancellations and modifications must be made at least 12 hours before the start time. Late cancellations
                and no-shows may be charged. Read the full details in our
                <a href="{{ route('info.show', 'cancellation-policy') }}">Class Cancellation &amp; Late Arrival Policy</a>.
            </p>
        </details>

        <details class="faq-item">
            <summary>Can I get a refund for a package?</summary>
            <p class="info-text">
                Class packages are non-refundable, non-exchangeable, and non-transferable. Each package has a validity period
                that starts from your first booking, and unused credits expire at the end of that period. See our
                <a href="{{ route('info.show', 'refund-policy') }}">Refund Policy</a> for details.
            </p>
        </details>

        <h2 class="info-section-title">RehabPlus Remote Monitoring</h2>

        <details class="faq-item">
            <summary>What is RehabPlus Remote Monitoring?</summary>
            <p class="info-text">
                It is a prescription-only tool for patients enrolled in a rehabilitation package. It uses AI-powered real-time
                pose estimation to help you follow your prescribed exercises.
            </p>
        </details>

        <details class="faq-item">
            <summary>Can I download the app or register on my own?</summary>
            <p class="info-text">
                No. There is no public registration. Access is given only to patients whose physiotherapist has prescribed it.
                Please speak with your therapist if you would like access.
            </p>
        </details>

        <p class="info-text mt-4 mb-0">
            This page does not replace medical advice. If you have severe pain, sudden weakness, numbness, or other urgent
            symptoms, seek medical care right away. For other questions, contact the clinic at
            <span class="fw-semibold">{{ $clinic['phone'] }}</span> or
            <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>.
        </p>
    </article>
@endsection
