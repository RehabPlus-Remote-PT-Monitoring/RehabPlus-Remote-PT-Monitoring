@extends('layouts.public')

@section('title', $title)

@section('content')
    <article class="info-page card shadow-sm border-0 p-4 p-lg-5 mx-auto">
        <a href="{{ route('landing') }}" class="small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

        <h1 class="info-page-title">{{ $title }}</h1>
        <p class="info-page-subtitle">{{ config('clinic.copyright') }} Refund Policy</p>

        <ul class="info-list">
            <li>
                All class packages purchased are strictly non-refundable, non-exchangeable and non-transferable.
            </li>
            <li>
                The validity period varies depending on the packages purchased.
            </li>
            <li>
                The specified validity period of each class package is activated from the date of first booking, and if no
                bookings are made, the validity period will run automatically after a pre-determined period.
            </li>
            <li>
                Each class credit must be utilized within the stipulated period from the date of package activation.
            </li>
            <li>
                It is essential for you to be aware of and adhere to the package's expiration date, as all unused credits
                would expire and cannot be used beyond this period.
            </li>
        </ul>

        <p class="info-text mb-0">
            For questions, contact the clinic at <span class="fw-semibold">{{ $clinic['phone'] }}</span> or
            <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>.
        </p>
    </article>
@endsection
