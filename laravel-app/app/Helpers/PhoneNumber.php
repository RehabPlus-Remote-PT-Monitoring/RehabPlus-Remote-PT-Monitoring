<?php

namespace App\Helpers;

/**
 * Phone numbers are stored as "+" followed by the country code and the national number,
 * for example +639171234567. The form picks the country, and the national number must have
 * the digits that country uses for mobile numbers (no trunk "0", no spaces).
 */
class PhoneNumber
{
    public const DEFAULT_COUNTRY = 'PH';

    public const FORMAT_MESSAGE = 'This phone number is either invalid or is in the wrong format.';

    /**
     * iso => [name, dial code, min digits, max digits, example national number, mobile number pattern].
     * The patterns check what the country's mobile numbers start with; they can't tell whether a
     * number is really in use. resources/js/input-masks.js applies the same checks in the browser.
     */
    private const COUNTRIES = [
        'PH' => ['Philippines', '63', 10, 10, '9171234567', '9\d{9}|8(?:13|9[5-9])\d{7}'],
        'US' => ['United States', '1', 10, 10, '2025550123', '[2-9]\d{2}[2-9]\d{6}'],
        'GB' => ['United Kingdom', '44', 10, 10, '7400123456', '7\d{9}'],
        'AU' => ['Australia', '61', 9, 9, '412345678', '4\d{8}'],
        'NZ' => ['New Zealand', '64', 8, 10, '212345678', '2\d{7,9}'],
        'SG' => ['Singapore', '65', 8, 8, '81234567', '[89]\d{7}'],
        'MY' => ['Malaysia', '60', 9, 10, '122345678', '1\d{8,9}'],
        'ID' => ['Indonesia', '62', 9, 12, '812345678', '8\d{8,11}'],
        'TH' => ['Thailand', '66', 9, 9, '812345678', '[689]\d{8}'],
        'VN' => ['Vietnam', '84', 9, 9, '912345678', '[35789]\d{8}'],
        'JP' => ['Japan', '81', 10, 10, '9012345678', '[789]0\d{8}'],
        'KR' => ['South Korea', '82', 10, 11, '1012345678', '1\d{9,10}'],
        'CN' => ['China', '86', 11, 11, '13812345678', '1[3-9]\d{9}'],
        'IN' => ['India', '91', 10, 10, '9812345678', '[6-9]\d{9}'],
        'HK' => ['Hong Kong', '852', 8, 8, '91234567', '[4-9]\d{7}'],
        'TW' => ['Taiwan', '886', 9, 9, '912345678', '9\d{8}'],
        'AE' => ['United Arab Emirates', '971', 9, 9, '501234567', '5\d{8}'],
        'SA' => ['Saudi Arabia', '966', 9, 9, '512345678', '5\d{8}'],
        'QA' => ['Qatar', '974', 8, 8, '33123456', '[3-7]\d{7}'],
        'KW' => ['Kuwait', '965', 8, 8, '50012345', '[4-69]\d{7}'],
        'DE' => ['Germany', '49', 10, 11, '15123456789', '1[567]\d{8,9}'],
        'FR' => ['France', '33', 9, 9, '612345678', '[67]\d{8}'],
        'IT' => ['Italy', '39', 9, 10, '3123456789', '3\d{8,9}'],
        'ES' => ['Spain', '34', 9, 9, '612345678', '[67]\d{8}'],
        'NL' => ['Netherlands', '31', 9, 9, '612345678', '6\d{8}'],
        'BR' => ['Brazil', '55', 11, 11, '11912345678', '[1-9]{2}9\d{8}'],
        'MX' => ['Mexico', '52', 10, 10, '5512345678', '[1-9]\d{9}'],
    ];

    /** @return list<array{iso: string, name: string, dial: string, min: int, max: int, digits: string, example: string, pattern: string}> */
    public static function countries(): array
    {
        return collect(self::COUNTRIES)
            ->map(fn (array $country, string $iso) => [
                'iso' => $iso,
                'name' => $country[0],
                'dial' => $country[1],
                'min' => $country[2],
                'max' => $country[3],
                'digits' => $country[2] === $country[3] ? "{$country[2]} digits" : "{$country[2]}–{$country[3]} digits",
                'example' => $country[4],
                'pattern' => $country[5],
            ])
            ->sortBy('name')
            ->values()
            ->all();
    }

    /** @return list<string> */
    public static function isoCodes(): array
    {
        return array_keys(self::COUNTRIES);
    }

    /** Null when the national number is valid for the country, otherwise the message to show. */
    public static function problem(string $iso, string $national): ?string
    {
        [$name, , $min, $max] = self::COUNTRIES[$iso];

        if (! ctype_digit($national)) {
            return 'Phone number can only contain numbers.';
        }

        $length = strlen($national);
        if ($length >= $min && $length <= $max) {
            if (str_starts_with($national, '0')) {
                return 'Leave out the 0 at the start of the phone number.';
            }

            return preg_match('/^(?:'.self::COUNTRIES[$iso][5].')$/', $national) && ! self::looksMadeUp($national)
                ? null
                : self::FORMAT_MESSAGE;
        }

        return $min === $max
            ? "Enter exactly {$min} digits for the phone number in {$name}."
            : "Enter {$min} to {$max} digits for the phone number in {$name}.";
    }

    /** All one digit, or digits simply counting up or down, like 9999999999 or 9876543210. */
    private static function looksMadeUp(string $national): bool
    {
        $steps = [];
        for ($i = 1; $i < strlen($national); $i++) {
            $steps[(int) $national[$i] - (int) $national[$i - 1]] = true;
        }

        return count($steps) === 1 && array_intersect_key($steps, [0 => 1, 1 => 1, -1 => 1]) !== [];
    }

    /** The stored form: "+" plus the country code and the national number. */
    public static function toStored(string $iso, string $national): string
    {
        return '+'.self::COUNTRIES[$iso][1].$national;
    }

    /**
     * A stored phone in the form a text message can be sent to, repairing older numbers
     * saved with a trunk "0". Empty stays empty; null when the digits can't be a real number.
     */
    public static function toE164(string $stored): ?string
    {
        if (trim($stored) === '') {
            return '';
        }

        $parsed = self::parse($stored);
        $national = ltrim($parsed['national'], '0');

        return self::problem($parsed['iso'], $national) === null ? self::toStored($parsed['iso'], $national) : null;
    }

    /** A stored phone for display, such as "+63 9171234567". */
    public static function display(string $stored): string
    {
        if ($stored === '') {
            return '';
        }

        $parsed = self::parse($stored);

        return '+'.self::COUNTRIES[$parsed['iso']][1].' '.$parsed['national'];
    }

    /**
     * The country and national number of a stored phone. Numbers saved before country codes
     * had no "+" and were taken as Philippine numbers, so a leading trunk "0" is dropped.
     *
     * @return array{iso: string, national: string}
     */
    public static function parse(?string $stored): array
    {
        $stored = trim((string) $stored);
        $digits = preg_replace('/\D/', '', $stored);

        if (str_starts_with($stored, '+')) {
            $match = collect(self::COUNTRIES)
                ->filter(fn (array $country) => str_starts_with($digits, $country[1]))
                ->sortByDesc(fn (array $country) => strlen($country[1]))
                ->keys()
                ->first();

            if ($match !== null) {
                return ['iso' => $match, 'national' => substr($digits, strlen(self::COUNTRIES[$match][1]))];
            }
        }

        return [
            'iso' => self::DEFAULT_COUNTRY,
            'national' => str_starts_with($digits, '0') ? substr($digits, 1) : $digits,
        ];
    }
}
