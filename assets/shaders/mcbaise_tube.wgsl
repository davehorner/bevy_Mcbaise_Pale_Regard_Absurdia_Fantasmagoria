#import bevy_pbr::forward_io::VertexOutput

// Pack everything into a single uniform buffer: WebGPU has a low per-stage uniform-buffer limit.
// Layout matches Rust `TubeMaterial.u: [Vec4; 6]`:
// [params0, params1, orange, white, dark_inside, dark_outside]
@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> u: array<vec4<f32>, 6>;
@group(#{MATERIAL_BIND_GROUP}) @binding(1) var fluid_velocity_texture: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(2) var fluid_velocity_sampler: sampler;
@group(#{MATERIAL_BIND_GROUP}) @binding(3) var fluid_density_texture: texture_2d<f32>;
@group(#{MATERIAL_BIND_GROUP}) @binding(4) var fluid_density_sampler: sampler;

const TAU: f32 = 6.28318530718;

fn aa_band(phase: f32, aa_mul: f32) -> f32 {
    let s = 0.5 + 0.5 * sin(phase);
    let w = fwidth(phase) * aa_mul;
    return smoothstep(0.5 - w, 0.5 + w, s);
}

@fragment
fn fragment(mesh: VertexOutput, @builtin(front_facing) is_front: bool) -> @location(0) vec4<f32> {
    let params0 = u[0];
    let params1 = u[1];
    let orange = u[2];
    let white = u[3];
    let dark_inside = u[4];
    let dark_outside = u[5];

    let time = params0.x;
    let bands = params0.y;
    let turns = params0.z;
    let spin = params0.w;

    let flow = params1.x;
    let aa = params1.y;
    let white_bias = params1.z;
    let pattern = params1.w;

    let ang = mesh.uv.y * TAU;
    let s = mesh.uv.x;

    let s_warp = pow(s, 1.18);

    // pattern 0: stripe, 1: swirl, 2: stripe wire, 3: swirl wire, 4: fluid, 5: fluid wire
    var phase: f32;
    let pattern_int = i32(floor(pattern + 0.5)); // Round to nearest integer
    
    if (pattern_int == 0) {
        // Pattern 0: stripe
        let theta = ang + s_warp * TAU * 16.0;
        phase = theta * (bands * 0.75) + time * (flow * 3.0);
    } else if (pattern_int == 1) {
        // Pattern 1: swirl
        let theta = ang + time * spin + s_warp * TAU * turns;
        phase = theta * bands + time * flow;
    } else if (pattern_int == 2) {
        // Pattern 2: stripe wire (same as stripe but with wireframe)
        let theta = ang + s_warp * TAU * 16.0;
        phase = theta * (bands * 0.75) + time * (flow * 3.0);
    } else if (pattern_int == 3) {
        // Pattern 3: swirl wire (same as swirl but with wireframe)
        let theta = ang + time * spin + s_warp * TAU * turns;
        phase = theta * bands + time * flow;
    } else {
        // Patterns 4+: fluid modes - phase will be set later in fluid logic
        phase = 0.0;
    }

    let band = aa_band(phase, aa);

    // Sample fluid textures if available (for fluid pattern mode)
    var fluid_influence = 0.0;
    var fluid_flow = 0.0;
    var fluid_vel = vec2<f32>(0.0, 0.0);
    var fluid_dens = 0.0;
    
    if (pattern_int >= 4) {
        fluid_vel = textureSample(fluid_velocity_texture, fluid_velocity_sampler, mesh.uv).rg;
        fluid_dens = textureSample(fluid_density_texture, fluid_density_sampler, mesh.uv).r;
        
        // Use fluid data to create fluid-driven pattern
        fluid_influence = fluid_dens * 4.0;
        fluid_flow = length(fluid_vel) * 1.0;
    }
    
    // Apply fluid modulation to the band pattern
    var final_band: f32;
    if (pattern_int >= 4) {
        // For fluid modes, create a fluid-driven pattern instead of modulating the base pattern
        let fluid_angle = atan2(fluid_vel.y, fluid_vel.x);
        let fluid_speed = length(fluid_vel);
        let fluid_phase = fluid_angle * bands + time * (flow * 2.0 + fluid_speed * 5.0) + fluid_dens * TAU;
        final_band = aa_band(fluid_phase, aa) * (1.0 + fluid_influence) + fluid_flow;
        
        // DEBUG: If fluid data is zero/constant, add some animation to verify fluid mode is active
        if (length(fluid_vel) < 0.01 && fluid_dens < 0.01) {
            // Fallback: show animated pattern to prove fluid mode is selected
            let debug_phase = mesh.uv.x * TAU * 4.0 + mesh.uv.y * TAU * 2.0 + time * 2.0;
            final_band = aa_band(debug_phase, aa);
        }
    } else {
        final_band = band;
    }
    
    let t = smoothstep(white_bias, 1.0, final_band);
    var col: vec3<f32>;
    if (pattern_int >= 4) {
        // For fluid modes, use fluid-based colors instead of orange/white
        let fluid_base = vec3<f32>(0.1, 0.3, 0.8);  // Blue base for fluid
        let fluid_highlight = vec3<f32>(0.8, 0.9, 1.0);  // Light blue/white highlight
        col = mix(fluid_base, fluid_highlight, t);
        
        // Add fluid velocity-based color variation
        let vel_color = vec3<f32>(
            fluid_vel.x * 0.5 + 0.5,  // Red from velocity X
            fluid_vel.y * 0.5 + 0.5,  // Green from velocity Y  
            1.0 - fluid_dens * 0.5    // Blue reduced by density
        );
        col = mix(col, vel_color, 0.3);  // Blend 30% velocity color
    } else {
        col = mix(white.rgb, orange.rgb, t);
    }

    let depth = smoothstep(0.0, 1.0, s);
    let dark = select(dark_inside.rgb, dark_outside.rgb, is_front);
    if (pattern_int >= 4) {
        // For fluid modes, use much lighter dark colors to preserve blue appearance
        let fluid_dark = vec3<f32>(0.2, 0.4, 0.6);  // Dark blue instead of dark red
        col = mix(col, fluid_dark, depth * 0.20);  // Reduce mixing to 20% for fluid modes
    } else {
        col = mix(col, dark, depth * 0.40);
    }

    return vec4<f32>(col, 1.0);
}
