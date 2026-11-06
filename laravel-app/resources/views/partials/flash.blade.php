@if (session('success'))
    <div class="alert alert-success">{{ session('success') }}</div>
@endif
{{-- Stays on screen: flash-messages.js only removes success and error messages. --}}
@if (session('warning'))
    <div class="alert alert-warning">{{ session('warning') }}</div>
@endif
@if (session('error'))
    <div class="alert alert-danger">{{ session('error') }}</div>
@endif
@if ($errors->any())
    <div class="alert alert-danger">
        <ul class="mb-0 ps-3">
            @foreach ($errors->all() as $message)
                <li>{{ $message }}</li>
            @endforeach
        </ul>
    </div>
@endif
