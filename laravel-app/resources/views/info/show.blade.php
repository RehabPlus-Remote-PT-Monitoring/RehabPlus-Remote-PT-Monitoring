@extends('layouts.public')

@section('title', $title)

@section('content')
    <div class="info-page card shadow-sm border-0 p-4 p-lg-5 mx-auto">
        <a href="{{ route('landing') }}" class="small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

        <h1 class="info-page-title">{{ $title }}</h1>

        <p class="text-muted mb-4">This page is being prepared. For questions, please contact the clinic:</p>

        <p class="mb-1 fw-semibold">{{ $clinic['phone'] }}</p>
        <p class="mb-0"><a href="mailto:{{ $clinic['email'] }}">{{ $clinic['email'] }}</a></p>
    </div>
@endsection
