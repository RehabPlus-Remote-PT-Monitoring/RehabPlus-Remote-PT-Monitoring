@extends('layouts.public')

@section('title', config('clinic.name'))

@section('content')
    @include('partials.clinic-hero')

    <div id="visit">
        @include('partials.clinic-info')
    </div>

    @include('partials.announcements', ['announcements' => $announcements])

    @include('partials.for-patients')

    <div id="classes">
        @include('partials.classes')
    </div>

    <div id="packages">
        @include('partials.clinic-packages')
    </div>

    <div id="about">
        @include('partials.about')
        @include('partials.staff-board')
        @include('partials.clinic-awards')
    </div>

    @include('partials.contact-cta')
@endsection
