<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('staff_schedules')) {
            Schema::create('staff_schedules', function (Blueprint $table) {
                $table->id();
                $table->string('staff', 150);
                $table->string('role', 100);
                $table->string('day', 20);
                $table->string('shift', 50);
                $table->string('room', 100)->default('General Room');
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('staff_time_offs')) {
            Schema::create('staff_time_offs', function (Blueprint $table) {
                $table->id();
                $table->string('staff', 150);
                $table->date('date');
                $table->string('type', 30)->default('Full day');
                $table->string('time', 50)->default('Full day');
                $table->string('reason', 255);
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_time_offs');
        Schema::dropIfExists('staff_schedules');
    }
};
