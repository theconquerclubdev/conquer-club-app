import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get all active members
    const { data: members, error: memberError } = await supabase
      .from('profiles')
      .select('id')
      .eq('role', 'member')
      .eq('is_active', true)

    if (memberError) throw memberError

    const today = new Date()
    const dateStr = today.toISOString().split('T')[0]
    const isSunday = today.getDay() === 0

    for (const member of members) {
      const memberId = member.id

      // 1. Check workout completion (45+ minutes)
      const startOfDay = new Date(today)
      startOfDay.setHours(0, 0, 0, 0)
      const endOfDay = new Date(today)
      endOfDay.setHours(23, 59, 59, 999)

      const { data: workout, error: workoutError } = await supabase
        .from('workout_sessions')
        .select('elapsed_seconds')
        .eq('member_id', memberId)
        .eq('status', 'completed')
        .gte('started_at', startOfDay.toISOString())
        .lte('started_at', endOfDay.toISOString())
        .maybeSingle()

      const workoutMinutes = workout ? Math.floor((workout.elapsed_seconds || 0) / 60) : 0
      const isWorkoutCompleted = workoutMinutes >= 45

      // 2. Get steps count and goal
      const { data: stepsLog, error: stepsError } = await supabase
        .from('step_logs')
        .select('steps')
        .eq('member_id', memberId)
        .eq('log_date', dateStr)
        .maybeSingle()

      const stepsCount = stepsLog?.steps || 0

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('step_goal')
        .eq('id', memberId)
        .maybeSingle()

      const stepGoal = profile?.step_goal || 10000
      const isStepsCompleted = stepsCount >= stepGoal

      // 3. Check photos uploaded (Sunday only)
      let isPhotosUploaded = false
      if (isSunday) {
        const { data: photos, error: photosError } = await supabase
          .from('member_progress_photos')
          .select('after_front, after_back')
          .eq('member_id', memberId)
          .maybeSingle()

        isPhotosUploaded = !!(photos?.after_front && photos?.after_back)
      }

      // 4. Check measurements updated (Sunday only)
      let isMeasurementsUpdated = false
      if (isSunday) {
        const { data: measurement, error: measurementError } = await supabase
          .from('measurement_logs')
          .select('recorded_at')
          .eq('member_id', memberId)
          .gte('recorded_at', startOfDay.toISOString())
          .lte('recorded_at', endOfDay.toISOString())
          .maybeSingle()

        isMeasurementsUpdated = !!measurement
      }

      // 5. Determine if streak is met
      let isStreakMet = false
      if (isSunday) {
        isStreakMet = isStepsCompleted && isPhotosUploaded && isMeasurementsUpdated
      } else {
        isStreakMet = isWorkoutCompleted && isStepsCompleted
      }

      // 6. Upsert streak record
      const { error: upsertError } = await supabase
        .from('member_streaks')
        .upsert({
          member_id: memberId,
          date: dateStr,
          is_workout_completed: isWorkoutCompleted,
          is_steps_completed: isStepsCompleted,
          is_photos_uploaded: isPhotosUploaded,
          is_measurements_updated: isMeasurementsUpdated,
          workout_minutes: workoutMinutes,
          steps_count: stepsCount,
          is_sunday: isSunday,
          is_streak_met: isStreakMet,
          updated_at: new Date().toISOString(),
        }, {
          onConflict: 'member_id,date'
        })

      if (upsertError) throw upsertError
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Streaks updated successfully' }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})