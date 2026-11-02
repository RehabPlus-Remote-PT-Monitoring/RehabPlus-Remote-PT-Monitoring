@extends('layouts.public')

@section('title', $title)

@section('content')
    <article class="info-page card shadow-sm border-0 p-4 p-lg-5 mx-auto">
        <a href="{{ route('landing') }}" class="small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

        <h1 class="info-page-title">{{ $title }}</h1>
        <p class="info-page-subtitle">{{ config('clinic.copyright') }}: Class Cancellation & Late Arrival Policy</p>

        <p class="info-text">
            Any class cancellation or modification must be made through our website at least 12 hours before your
            scheduled booking. Cancellations or modifications communicated via text or email will not be considered valid.
        </p>

        <ul class="info-list">
            <li>
                <strong>Early Cancellations:</strong> No credits will be deducted for any cancellations or modifications
                made prior to 12 hours of the start time.
            </li>
            <li>
                <strong>Late Cancellations:</strong> A full class credit will be deducted for any cancellations or
                modifications made within 12 hours of the start time.
            </li>
            <li>
                <strong>Class Late Arrivals:</strong> We encourage participants to arrive at least 15 minutes early to
                check in and prepare for class. For safety reasons, we implement a strict late-arrival policy to prevent
                disruptions and to ensure a positive and focused environment for all participants.
            </li>
            <li>
                <strong>Private/Duet Late Arrivals:</strong> If participant(s) fail to show up or arrive on time for an
                in-person or duet appointment, the designated instructor will wait only for 10 minutes, and the class
                will end as scheduled. Late arrivals exceeding 10 minutes will be treated as late cancellations, and no
                credit refund will be provided.
            </li>
            <li>
                <strong>No shows:</strong> If participant(s) fail to show up or arrive on time, these will be treated as
                late cancellations, and no credit refund will be provided.
            </li>
        </ul>

        <p class="info-text mb-0">
            For questions, contact the clinic at <span class="fw-semibold">{{ $clinic['phone'] }}</span> or
            <a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a>.
        </p>
    </article>
@endsection
