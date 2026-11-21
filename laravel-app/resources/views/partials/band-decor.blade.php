{{-- Decoration behind the Remote Monitoring band: exercise figures drawn with pose-estimation joints, plus fitness icons. Purely visual. --}}
<svg class="patient-band-svg" viewBox="0 0 1200 600" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
    <g fill="none" stroke="currentColor" stroke-width="2" stroke-opacity=".14">
        <circle cx="1130" cy="40" r="190"/>
        <circle cx="1130" cy="40" r="270"/>
        <circle cx="30" cy="620" r="230"/>
    </g>

    {{-- A figure doing a squat with raised arms, with the joints an AI pose estimator would track. --}}
    <g transform="translate(120 300) scale(1.15)" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity=".2" fill="none">
        <circle cx="0" cy="-100" r="14" stroke-width="4"/>
        <line x1="0" y1="-84" x2="0" y2="-2"/>
        <line x1="-24" y1="-74" x2="24" y2="-74"/>
        <polyline points="-24,-74 -48,-48 -62,-70"/>
        <polyline points="24,-74 48,-48 62,-70"/>
        <line x1="-16" y1="-2" x2="16" y2="-2"/>
        <polyline points="-16,-2 -40,38 -28,80"/>
        <polyline points="16,-2 40,38 28,80"/>
    </g>
    <g fill="currentColor" fill-opacity=".3" transform="translate(120 300) scale(1.15)">
        <circle cx="-24" cy="-74" r="5"/><circle cx="24" cy="-74" r="5"/>
        <circle cx="-48" cy="-48" r="5"/><circle cx="48" cy="-48" r="5"/>
        <circle cx="-62" cy="-70" r="5"/><circle cx="62" cy="-70" r="5"/>
        <circle cx="-16" cy="-2" r="5"/><circle cx="16" cy="-2" r="5"/>
        <circle cx="-40" cy="38" r="5"/><circle cx="40" cy="38" r="5"/>
        <circle cx="-28" cy="80" r="5"/><circle cx="28" cy="80" r="5"/>
    </g>

    {{-- A second figure, a lunge, further right and smaller. --}}
    <g transform="translate(1010 470) scale(.85)" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity=".16" fill="none">
        <circle cx="0" cy="-100" r="14" stroke-width="4"/>
        <line x1="0" y1="-84" x2="-6" y2="-6"/>
        <line x1="-24" y1="-74" x2="24" y2="-74"/>
        <polyline points="-24,-74 -40,-40 -22,-14"/>
        <polyline points="24,-74 40,-40 22,-14"/>
        <polyline points="-6,-6 -40,30 -48,80"/>
        <polyline points="-6,-6 30,36 24,80"/>
    </g>

    {{-- Fitness icons. --}}
    <g fill="currentColor" fill-opacity=".16" transform="translate(640 110) scale(1.3)">
        <rect x="-38" y="-10" width="10" height="20" rx="3"/>
        <rect x="-28" y="-16" width="8" height="32" rx="2"/>
        <rect x="-20" y="-2" width="40" height="4"/>
        <rect x="20" y="-16" width="8" height="32" rx="2"/>
        <rect x="28" y="-10" width="10" height="20" rx="3"/>
    </g>

    <g fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity=".18">
        <polyline points="330,540 370,540 386,500 404,580 422,512 438,540 520,540"/>
        <circle cx="880" cy="110" r="34"/>
        <line x1="880" y1="110" x2="880" y2="86"/>
        <line x1="880" y1="110" x2="896" y2="124"/>
        <line x1="866" y1="60" x2="894" y2="60"/>
    </g>

    <g fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity=".16">
        <circle cx="560" cy="500" r="20"/>
        <polyline points="552,500 558,508 572,490"/>
    </g>
</svg>
