import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // ✅ Single set-based SQL function does the work for every active
    // member in one query, instead of looping here with ~5 queries
    // per member. Same rules, same output table (member_streaks).
    const { error } = await supabase.rpc('update_daily_member_streaks')

    if (error) throw error

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
