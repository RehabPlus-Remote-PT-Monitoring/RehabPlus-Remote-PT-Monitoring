<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StaffSchedule extends Model
{
    protected $table = 'staff_schedules';

    protected $fillable = [
        'staff',
        'role',
        'day',
        'shift',
        'room',
    ];
}
