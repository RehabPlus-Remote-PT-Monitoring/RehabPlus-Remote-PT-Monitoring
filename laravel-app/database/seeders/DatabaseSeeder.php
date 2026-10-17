<?php

namespace Database\Seeders;

use App\Models\Appointment;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

/**
 * Demo data for the modules still on SQL (appointments). Staff accounts and
 * patients live in Firebase: create the first admin with
 * `php artisan rehab:make-admin`, then add staff and patients from the dashboard.
 */
class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        Appointment::query()->truncate();

        Appointment::create([
            'patient' => 'Emily Johnson',
            'therapist' => 'Dr. Sarah Lee',
            'patient_condition' => 'Knee Rehabilitation',
            'contact' => '555-1201',
            'date' => now()->addDay()->toDateString(),
            'time' => '09:30:00',
            'session' => 'Mobility Session',
            'notes' => 'Focus on knee flexion and gait improvement.',
            'status' => 'Upcoming',
        ]);

        Appointment::create([
            'patient' => 'Marcus Smith',
            'therapist' => 'Dr. Sarah Lee',
            'patient_condition' => 'Back Recovery',
            'contact' => '555-9840',
            'date' => now()->addDays(2)->toDateString(),
            'time' => '14:00:00',
            'session' => 'Strength Review',
            'notes' => 'Review posture and recovery trend.',
            'status' => 'Upcoming',
        ]);
    }
}
