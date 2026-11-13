<?php

namespace App\Services\Patient;

/**
 * A temporary password for a new patient's app login, such as "StretchBalance4821".
 * Two random words and four random digits, with no spaces or hyphens, so it is easy
 * to read out and type, and long enough for the minimum password length. The patient
 * changes it in the app with "Forgot password".
 */
class TemporaryPassword
{
    /* Physical therapy, Pilates, and recovery words. */
    private const WORDS = [
        'Stretch', 'Balance', 'Posture', 'Motion', 'Healing', 'Pilates', 'Reformer', 'Flexion',
        'Mobility', 'Recover', 'Strength', 'Core', 'Lumbar', 'Tendon', 'Ligament', 'Gentle',
        'Rebound', 'Spine', 'Cadence', 'Agility', 'Vitality', 'Rhythm', 'Flow', 'Anchor',
        'Stride', 'Wellness', 'Resilient', 'Breathe', 'Harmony', 'Steady', 'Upright', 'Glide',
        'Therapy', 'Rehab', 'Lengthen', 'Align', 'Pivot', 'Momentum', 'Recovery', 'Tonic',
    ];

    public static function generate(): string
    {
        $first = self::WORDS[random_int(0, count(self::WORDS) - 1)];
        $second = self::WORDS[random_int(0, count(self::WORDS) - 1)];

        return $first.$second.random_int(1000, 9999);
    }
}
