<?php

/*
 * Clinic details shown on the Home page. Edit here; no code changes needed.
 *
 * Awards: one entry per award or certification, newest first.
 *   'title'  required, the award name
 *   'issuer' optional, who gave it
 *   'year'   optional
 *   'icon'   optional Bootstrap Icons class, e.g. 'bi-patch-check-fill'
 */

return [
    'name' => 'Rehab+ Physiotherapy & Pilates',
    'subtitle' => 'Physical Therapy + Clinical Pilates',

    /* The footer line, after the copyright symbol and year. */
    'copyright' => 'Rehab+ Physiotherapy & Pilates',

    'schedule' => [
        ['days' => 'Monday to Saturday', 'hours' => '9:00am – 6:00pm'],
        ['days' => 'Sunday', 'hours' => '9:00am – 4:00pm'],
    ],

    'location' => '1308 Benavidez St, Metro Manila',
    'map_url' => 'https://maps.app.goo.gl/ftDwzQCMAVh1mfXE9',
    'phone' => '0912 854 8156',
    'email' => 'rehabplusphysiotherapy24@gmail.com',
    'facebook' => 'https://www.facebook.com/profile.php?id=61577141983895',
    'instagram' => 'https://www.instagram.com/rehabplus.physiotherapy',

    /*
     * Price lists shown in the Packages section. 'image' is a file in public/assets/images/packages/.
     */
    'packages' => [
        ['title' => 'Pilates packages', 'image' => 'assets/images/packages/pilates-packages.png'],
        ['title' => 'Rehab packages', 'image' => 'assets/images/packages/rehab-packages.png'],
    ],

    /*
     * The classes shown in the Classes section. 'image' is a file in public/assets/images/classes/.
     * 'duration' is the class length; 'level' is shown as the class's level.
     */
    'classes' => [
        [
            'title' => 'Jumpboard Flow Class',
            'duration' => '50 mins',
            'level' => 'Advanced',
            'image' => 'assets/images/classes/jumpboard-flow.jpg',
            'description' => 'A class designed to improve leg strength, core stability, coordination, and endurance while being gentle on the joints.',
        ],
        [
            'title' => 'Strong & Centered',
            'duration' => '50 mins',
            'level' => 'Advanced',
            'image' => 'assets/images/classes/strong-and-centered.jpg',
            'description' => 'A class designed to challenge strength, control, and precision. This session focuses on powerful core work and complex movement patterns.',
        ],
        [
            'title' => 'Essentials',
            'duration' => '50 mins',
            'level' => 'Beginner',
            'image' => 'assets/images/classes/essentials.jpg',
            'description' => 'A beginner Pilates class, ideal for first-timers and anyone focusing on the foundations of Pilates.',
        ],
        [
            'title' => 'Flow & Lengthen',
            'duration' => '50 mins',
            'level' => 'Intermediate',
            'image' => 'assets/images/classes/flow-and-lengthen.jpg',
            'description' => 'A class designed to improve mobility, posture, and full-body control. It emphasizes fluid transitions, gentle strengthening, and intentional stretching.',
        ],
        [
            'title' => 'Clinical Pilates (Private)',
            'duration' => '50 mins',
            'level' => 'Open to all',
            'image' => 'assets/images/classes/clinical-pilates-private.jpg',
            'description' => 'A one-on-one session on the reformer or chair, tailored to your body and goals. Ideal for focused progress, injury considerations, and personalized guidance throughout your session.',
        ],
        [
            'title' => 'Private Duo',
            'duration' => '50 mins',
            'level' => 'Open to all',
            'image' => 'assets/images/classes/private-duo.jpg',
            'description' => 'Train with a partner in a semi-private setting designed for personalized attention and shared motivation. Perfect for friends, couples, or training partners.',
        ],
        [
            'title' => 'Pilatherapy',
            'duration' => '120 mins',
            'level' => 'Open to all',
            'image' => 'assets/images/classes/pilatherapy.jpg',
            'description' => 'A comprehensive, therapist-led program combining Pilates-based movement with clinical physical therapy and specialized PT machines. Designed to relieve pain, restore movement, and build strength.',
        ],
    ],

    /* Pages linked from the footer. Their text is still to be written by the clinic. */
    'info_pages' => [
        'faq' => 'FAQ',
        'cancellation-policy' => 'Class Cancellation & Late Arrival Policy',
        'refund-policy' => 'Refund Policy',
        'terms' => 'Terms & Conditions',
    ],

    /* The RehabPlus Remote Monitoring page, linked from the Learn more button on the welcome page. */
    'remote_monitoring' => [
        'steps' => [
            ['title' => 'Sign in', 'text' => 'Use the account your clinic created for you.'],
            ['title' => 'Do your exercises', 'text' => 'Your prescribed exercises appear in your plan. The camera checks your form and counts your repetitions as you go.'],
            ['title' => 'Track your progress', 'text' => 'Log your pain level after each session, and see your progress and messages from your therapist and clinic.'],
        ],
        'features' => [
            ['icon' => 'bi-camera-video', 'title' => 'Camera-based guidance', 'text' => 'AI-powered pose estimation follows your movements through the phone camera while you exercise.'],
            ['icon' => 'bi-check2-circle', 'title' => 'Real-time form feedback', 'text' => 'Get feedback on your form during each exercise, so you can correct your movement as you go.'],
            ['icon' => 'bi-123', 'title' => 'Repetitions and compliance', 'text' => 'Your repetitions and completed sessions are counted automatically, so your therapist can see how you are doing.'],
            ['icon' => 'bi-list-check', 'title' => 'Your exercise plan', 'text' => 'See the exercises your therapist prescribed, with a daily checklist and a weekly progress bar.'],
            ['icon' => 'bi-heart-pulse', 'title' => 'Pain level tracking', 'text' => 'Log how you feel after each session, so your therapist can adjust your program.'],
            ['icon' => 'bi-graph-up', 'title' => 'Progress over time', 'text' => 'Review your stats for the last 7, 30, and 90 days, with trends for your sessions and time.'],
            ['icon' => 'bi-bullseye', 'title' => 'Goals from your therapist', 'text' => 'See the recovery goals your therapist has set for you.'],
            ['icon' => 'bi-chat-dots', 'title' => 'Messages with your clinic', 'text' => 'Message your therapist and the clinic, and get notified when there is a reply.'],
            ['icon' => 'bi-bell', 'title' => 'Reminders and notifications', 'text' => 'Get reminders for your exercises and updates from your clinic.'],
            ['icon' => 'bi-cast', 'title' => 'Cast to a TV', 'text' => 'Enjoy a bigger view of your exercises. Mirror your screen to a TV and follow along comfortably from across the room.'],
            ['icon' => 'bi-moon-stars', 'title' => 'Light and dark mode', 'text' => 'Choose a light, dark, or phone-based theme in Settings.'],
            ['icon' => 'bi-shield-lock', 'title' => 'Optional PIN lock', 'text' => 'Protect the app with a PIN.'],
        ],
    ],

    'awards' => [],
];
