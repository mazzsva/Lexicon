//
//  GenerationGlow.metal
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 18/10/26.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float tau = 6.2831853;
constant float lineInset = 1.75;
constant float launch = 0.1;
constant float meet = 0.8;
constant float homeArrival = 0.72;
constant float orbInset = 29.0;
constant float orbReach = 50.0;

constant float3 lightPalette[7] = {
    float3(0.22, 0.62, 1.00),
    float3(0.18, 0.40, 1.00),
    float3(0.55, 0.30, 1.00),
    float3(0.95, 0.24, 0.62),
    float3(1.00, 0.40, 0.32),
    float3(1.00, 0.62, 0.30),
    float3(1.00, 0.74, 0.16)
};

constant float3 darkPalette[7] = {
    float3(0.30, 0.78, 1.00),
    float3(0.33, 0.50, 1.00),
    float3(0.66, 0.40, 1.00),
    float3(1.00, 0.36, 0.78),
    float3(1.00, 0.47, 0.42),
    float3(1.00, 0.70, 0.32),
    float3(1.00, 0.82, 0.24)
};

static float continuousBoxDistance(float2 p, float2 halfSize, float radius) {
    float r = radius * 1.25;
    float2 q = abs(p) - halfSize + r;
    if (q.x > 0.0 && q.y > 0.0) {
        float2 corner = pow(q, 2.64);
        return pow(corner.x + corner.y, 1.0 / 2.64) - r;
    }
    return max(q.x, q.y) - r;
}

static float quadrantArc(float2 q, float2 b, float r) {
    float2 w = float2(q.x - b.x, -q.y - b.y);
    float a = (w.x > 0.0 && w.y > 0.0) ? atan2(w.x, w.y) : (w.x > 0.0 ? 0.5 * M_PI_F : 0.0);
    return min(q.x, b.x) + a * r + max(q.y + b.y, 0.0);
}

static float perimeterCoordinate(float2 q, float2 b, float r, float perimeterLength) {
    float quarter = 0.25 * perimeterLength;
    float s;
    if (q.x >= 0.0 && q.y < 0.0) {
        s = quadrantArc(q, b, r);
    } else if (q.x >= 0.0) {
        s = quarter + quadrantArc(float2(q.y, -q.x), b.yx, r);
    } else if (q.y >= 0.0) {
        s = 2.0 * quarter + quadrantArc(-q, b, r);
    } else {
        s = 3.0 * quarter + quadrantArc(float2(-q.y, q.x), b.yx, r);
    }
    return s / perimeterLength;
}

static float triangle(float x) {
    return 1.0 - abs(2.0 * fract(x) - 1.0);
}

static float3 paletteColor(float x, float dark) {
    float f = clamp(x, 0.0, 1.0) * 6.0;
    int i = min(int(f), 5);
    float m = f - float(i);
    float3 lightColor = mix(lightPalette[i], lightPalette[i + 1], m);
    float3 darkColor = mix(darkPalette[i], darkPalette[i + 1], m);
    return mix(lightColor, darkColor, dark);
}

[[ stitchable ]] half4 generationGlow(
    float2 position,
    half4 color,
    float2 size,
    float cornerRadius,
    float time,
    float writingStart,
    float completion,
    float completionDuration,
    float dark,
    float mirrored,
    device const float *pulses,
    int pulseCount
) {
    float outro = (time - completion) / max(completionDuration, 0.001);
    if (outro >= 1.0) {
        return half4(0.0);
    }
    float2 halfSize = size * 0.5;
    float2 q = position - halfSize;
    q.x = mirrored > 0.5 ? -q.x : q.x;
    float radius = min(cornerRadius, min(halfSize.x, halfSize.y) * 0.8);
    float e = -continuousBoxDistance(q, halfSize, radius);
    float orbDistance = length(q - (halfSize - orbInset));
    if (e > 64.0 && orbDistance > orbReach) {
        return half4(0.0);
    }
    float edge = max(e, 0.0);
    float across = e - lineInset;

    float skeleton = min(halfSize.x, halfSize.y) * 0.9;
    float2 b = max(halfSize - skeleton, 0.0);
    float perimeterLength = 4.0 * (b.x + b.y) + tau * skeleton;
    float halfLength = 0.5 * perimeterLength;
    float u = perimeterCoordinate(q, b, skeleton, perimeterLength);
    float originU = 0.25 + (b.y + 0.25 * M_PI_F * skeleton) / perimeterLength;
    float span = abs(fract(u - originU + 0.5) - 0.5) * perimeterLength;
    float soften = 2.0 + 1.2 * edge;
    float nearOrigin = sqrt(span * span + soften * soften) - soften;
    float nearMeet = sqrt((halfLength - nearOrigin) * (halfLength - nearOrigin) + soften * soften) - soften;
    float path = halfLength - nearMeet;

    float breath = smoothstep(0.0, 1.0, triangle(time / 3.6));
    float writingFrom = max(writingStart, meet + 0.45);
    float writing = smoothstep(writingFrom, writingFrom + 0.5, time);
    float thinking = 1.0 - writing;
    float calmBreath = breath * thinking;

    float x = clamp((time - launch) / (meet - launch), 0.0, 1.0);
    float progress = mix(x, x * x * (3.0 - 2.0 * x), 0.75);
    float introSpeed = halfLength * mix(1.0, 6.0 * x * (1.0 - x), 0.75) / (meet - launch);
    float front = progress * (halfLength + 10.0);
    float behind = path - front;
    float ignite = smoothstep(0.0, 0.12, time);
    float settled = smoothstep(meet - 0.05, meet + 0.06, time);
    float lit = max(1.0 - smoothstep(-8.0, 2.0, behind), settled) * ignite;
    float comet = smoothstep(launch - 0.02, launch + 0.06, time) * (1.0 - smoothstep(meet - 0.02, meet + 0.06, time));
    float flash = smoothstep(meet - 0.05, meet, time) * (1.0 - smoothstep(meet, meet + 0.3, time));
    float bud = ignite * (1.0 - smoothstep(launch + 0.04, launch + 0.24, time));
    float grow = 0.4 + 0.6 * smoothstep(0.1, 1.1, time);
    float settle = 1.0 + 0.25 * smoothstep(meet - 0.05, meet + 0.08, time)
        * (1.0 - smoothstep(meet + 0.08, meet + 0.6, time));

    float pulseGate = smoothstep(meet + 0.2, meet + 0.5, time);
    float pulse = 0.0;
    float kick = 0.0;
    float activity = 0.0;
    for (int i = 0; i < min(pulseCount, 8); i++) {
        float age = time - pulses[i];
        if (age < 0.0 || age > 0.85) {
            continue;
        }
        float envelope = smoothstep(0.0, 0.07, age) * (1.0 - smoothstep(0.15, 0.85, age));
        float a = age / 0.85;
        float pulseFront = 0.6 * halfLength * a * sqrt(a);
        float beyond = max(nearOrigin - pulseFront, 0.0) / (24.0 + 60.0 * age);
        pulse = max(pulse, envelope * exp(-beyond * beyond));
        kick += smoothstep(0.0, 0.06, age) * exp(-age / 0.14);
        activity += envelope;
    }
    float kickSpread = nearOrigin / (0.45 * halfLength);
    float pump = min(kick, 1.0) * pulseGate;
    float tick = pump * exp(-kickSpread * kickSpread);
    float swell = min(0.5 * pulse * pulseGate + 0.5 * tick, 1.0);
    float lively = activity * pulseGate / (activity * pulseGate + 3.0);

    float trail = 0.0;
    float head = 0.0;
    float2 headOffset = float2(0.0);
    if (comet > 0.0) {
        trail = exp(min(behind, 0.0) / max(60.0, 0.1 * halfLength)) * (1.0 - smoothstep(-2.0, 2.0, behind))
            * comet * (1.0 - settled);
        float lightHead = smoothstep(launch, launch + 0.18, time) * (1.0 - smoothstep(meet - 0.1, meet, time));
        head = comet * mix(lightHead, 1.0 - 0.5 * smoothstep(meet - 0.12, meet, time), dark);
        headOffset = float2(behind + 2.0, across);
    }

    float keep = 1.0;
    float exit = 1.0;
    float homeTrail = 0.0;
    float homeHead = 0.0;
    float homeSpeed = 0.0;
    float2 homeOffset = float2(0.0);
    float glint = 0.0;
    if (outro >= 0.0) {
        float h = clamp(outro / homeArrival, 0.0, 1.0);
        float homeProgress = mix(h * (0.35 + 0.65 * h), h * h * (3.0 - 2.0 * h), 0.4);
        homeSpeed = halfLength * mix(0.35 + 1.3 * h, 6.0 * h * (1.0 - h), 0.4) / (homeArrival * completionDuration);
        float ahead = path - halfLength * (1.0 - homeProgress);
        float drained = 1.0 - smoothstep(0.66, 0.84, outro);
        keep = (1.0 - smoothstep(-2.0, 10.0, ahead)) * drained;
        float tail = max(1.0, halfLength / 600.0);
        homeTrail = exp(-max(ahead, 0.0) / (mix(45.0, 70.0, h) * tail))
            * (1.0 - smoothstep(60.0, 150.0 * tail, ahead))
            * smoothstep(-2.0, 2.0, ahead) * (1.0 - smoothstep(0.7, 0.92, outro));
        homeHead = smoothstep(0.0, 0.06, outro) * (1.0 - smoothstep(mix(0.68, 0.72, dark), 0.8, outro));
        homeOffset = float2(ahead - 2.0, across);
        glint = smoothstep(0.66, 0.78, outro) * (1.0 - smoothstep(0.8, 1.0, outro));
        exit = 1.0 - smoothstep(0.86, 1.0, outro);
    }

    float2 widthWave = sin(tau * float2(1.0, 3.0) * u + float2(0.9, -1.7) * time + float2(0.0, 4.1));
    float2 brightWave = sin(tau * float2(2.0, 5.0) * u + float2(-0.8, 1.9) * time + float2(2.2, 5.3));
    float width = 1.0 + (0.2 + 0.08 * writing) * dot(widthWave, float2(0.6, 0.4));
    float shimmer = dot(brightWave, float2(0.6, 0.4));
    float bright = 1.0 + (0.12 + 0.12 * writing) * shimmer;
    float2 flowWave = sin(tau * float2(2.0, 3.0) * u + float2(1.1, -0.8) * time);
    float flow = u - 0.045 * time + dot(flowWave, float2(0.1, 0.07)) + 0.04 * writing * shimmer;
    float hue = triangle(flow) * mix(0.62, 1.0, writing);

    float meetLight = 0.0;
    float closing = 0.0;
    float closeAge = time - meet;
    if (closeAge > -0.05 && closeAge < 0.6) {
        float wave = halfLength * smoothstep(0.0, 0.5, closeAge);
        float waveWidth = 30.0 + 0.06 * halfLength;
        float lag = (nearMeet - wave) / waveWidth;
        closing = exp(-lag * lag) * smoothstep(-0.05, 0.02, closeAge) * (1.0 - smoothstep(0.4, 0.6, closeAge));
        meetLight = 0.4 * dark * flash * exp(-length(float2(nearMeet / 4.0, 1.6 * across)) / 6.0);
    }
    float budBoost = bud * exp(-(span / 40.0) * (span / 40.0));
    float labelDistance = length(q + halfSize - float2(16.0, 21.0));
    float nearLabel = (1.0 - smoothstep(16.0, 56.0, labelDistance)) * smoothstep(1.0, 4.0, across);
    float hush = 1.0 - 0.85 * nearLabel;
    float labelGuard = 1.0 - 0.75 * nearLabel * clamp(comet + closing + flash, 0.0, 1.0);
    float lighten = (1.0 - dark) * clamp(budBoost + mix(0.9, 0.6, dark) * closing, 0.0, 1.0) * hush;

    float energy = bright * settle * (1.0 + 0.5 * lively) * (1.0 + 0.8 * swell);
    float streak = 1.0 + mix(0.8, 1.4, dark) * trail + 1.2 * homeTrail + mix(1.3, 0.9, dark) * closing;
    float coreWidth = mix(1.7, 1.4, writing) * (0.8 + 0.2 * width) * (1.0 + mix(0.3, 0.6, dark) * swell);
    float core = exp(-(across / coreWidth) * (across / coreWidth));
    float haloRadius = mix(6.0, 4.5, writing) * width * (1.0 + 0.3 * calmBreath) * (1.0 + 0.15 * lively)
        * (1.0 + mix(0.6, 0.8, dark) * swell) * (1.0 + 0.6 * lighten);
    float halo = exp(-edge / haloRadius);
    float reach = max(mix(14.0, 11.0, writing) * width * grow * (1.0 + 0.3 * calmBreath) * (1.0 + 0.45 * swell), 1.0);
    float bloom = exp(-edge / reach) * (1.0 - smoothstep(0.0, min(mix(3.0, 3.2, dark) * reach, 48.0), edge));

    float base = lit * max(keep, homeTrail) * exit;
    float coreGain = mix(mix(0.55, 0.8, writing), mix(0.55, 0.95, writing), dark);
    float haloGain = mix(mix(0.36, 0.45, writing), mix(0.42, 0.6, writing), dark);
    float bloomGain = mix(mix(0.18, 0.12, writing), mix(0.42, 0.5, writing), dark);
    float coreAlpha = clamp(core * energy * streak * base * coreGain, 0.0, 1.0);
    float haloAlpha = halo * energy * (0.7 + 0.3 * mix(1.0, streak, hush)) * base * haloGain
        * (0.85 + 0.15 * calmBreath) * (1.0 + mix(0.5, 0.9, dark) * swell) * (1.0 + 0.5 * lighten);
    float bloomAlpha = bloom * energy * base * bloomGain;

    float3 coreColor = paletteColor(hue + 0.08 + 0.04 * swell, dark);
    float3 haloColor = paletteColor(hue + 0.04 * swell, dark);
    float3 bloomColor = paletteColor(hue - edge * 0.005, dark);
    float softening = 0.32 * (1.0 - dark);
    haloColor = mix(haloColor, float3(1.0), softening);
    bloomColor = mix(bloomColor, float3(1.0), softening);
    float whiteness = clamp(mix(0.3, 0.5, writing) + 0.7 * swell + trail + homeTrail + 0.6 * closing, 0.0, 1.0);
    float3 lightCore = mix(coreColor * mix(1.0, 0.92, writing), float3(1.0), 0.4 * lighten);
    float3 coreTint = mix(lightCore, mix(coreColor, float3(1.0), 0.6 * whiteness), dark);

    float glowAlpha = clamp(haloAlpha + bloomAlpha, 0.0, 1.0);
    float3 glowColor = mix(bloomColor, haloColor, haloAlpha / max(haloAlpha + bloomAlpha, 1e-4));
    float3 premultiplied = coreTint * coreAlpha + glowColor * glowAlpha * (1.0 - coreAlpha);
    float alpha = coreAlpha * mix(1.0, 0.8, dark) + glowAlpha * (1.0 - coreAlpha) * mix(1.0, 0.55, dark);

    float orbIn = smoothstep(0.0, 0.09, time) * (1.0 - smoothstep(0.12, 0.32, time));
    float orbReturn = smoothstep(0.35, 0.5, closeAge) * (1.0 - smoothstep(0.5, 0.85, closeAge));
    float orbLight = orbIn + mix(0.6, 0.35, dark) * orbReturn + 0.7 * pump + glint;
    if (orbLight > 0.0 && orbDistance < orbReach) {
        float ringRadius = orbIn > 0.0 ? mix(20.0, 35.0, smoothstep(0.0, 0.16, time)) : mix(34.0, 19.0, glint);
        float ringOffset = (orbDistance - ringRadius) / mix(3.5, 5.5, dark);
        float ring = (orbIn + glint) * exp(-ringOffset * ringOffset);
        float orbCore = orbLight * exp(-(orbDistance / 24.0) * (orbDistance / 24.0));
        float3 orbHue = paletteColor(hue + 0.12, dark);
        float orbFade = 1.0 - smoothstep(orbReach - 10.0, orbReach, orbDistance);
        float orbAlpha = clamp((0.55 * ring + 0.5 * orbCore) * mix(0.7, 1.0, dark) * exit * orbFade, 0.0, 1.0);
        float3 orbColor = mix(orbHue, float3(1.0), mix(0.3, 0.45 + 0.3 * orbCore, dark));
        premultiplied = orbColor * orbAlpha + premultiplied * (1.0 - orbAlpha);
        alpha = orbAlpha * mix(1.0, 0.7, dark) + alpha * (1.0 - orbAlpha);
    }

    if (head + homeHead + bud + meetLight > 0.0) {
        float3 sparkHue = paletteColor(hue + 0.2, dark);
        float budRadius = length(float2(span, across));
        float budSize = mix(3.0, mix(7.0, 5.5, dark), smoothstep(0.0, 0.12, time));
        float sparkAlpha;
        float3 sparkColor;
        if (dark > 0.5) {
            float headRadius = length(headOffset);
            float homeRadius = length(homeOffset);
            float2 headHot = headOffset / float2(max(2.6, 1.1 * introSpeed / 120.0), 2.6);
            float2 homeHot = homeOffset / float2(max(2.6, 1.1 * homeSpeed / 120.0), 2.6);
            float fringe = head * exp(-headRadius / 9.0) + homeHead * exp(-homeRadius / 9.0)
                + bud * exp(-budRadius / budSize) + meetLight;
            float hot = head * exp(-dot(headHot, headHot)) + homeHead * exp(-dot(homeHot, homeHot))
                + bud * exp(-(budRadius / 2.2) * (budRadius / 2.2))
                + 0.3 * meetLight;
            sparkAlpha = fringe;
            sparkColor = mix(sparkHue, float3(1.0), clamp(hot * 1.5 + 0.25, 0.0, 1.0));
        } else {
            float2 headShape = headOffset / float2(10.0, 2.2);
            float2 homeShape = homeOffset / float2(10.0, 2.2);
            float comets = head * exp(-dot(headShape, headShape)) + homeHead * exp(-dot(homeShape, homeShape));
            float budLight = 0.5 * bud * exp(-(budRadius / budSize) * (budRadius / budSize));
            sparkAlpha = comets + budLight;
            float3 mixed = sparkHue * 0.82 * comets + mix(sparkHue, float3(1.0), 0.3) * budLight;
            sparkColor = mixed / max(sparkAlpha, 1e-4);
        }
        sparkAlpha = clamp(sparkAlpha * exit * hush, 0.0, 1.0);
        premultiplied = sparkColor * sparkAlpha + premultiplied * (1.0 - sparkAlpha);
        alpha = sparkAlpha * mix(1.0, 0.75, dark) + alpha * (1.0 - sparkAlpha);
    }

    alpha = clamp(alpha * labelGuard, 0.0, 1.0);
    premultiplied *= labelGuard;
    float noise = fract(52.9829189 * fract(dot(position, float2(0.06711056, 0.00583715))));
    premultiplied += (noise - 0.5) / 255.0 * min(alpha * 8.0, 1.0);
    return half4(half3(clamp(premultiplied, 0.0, mix(alpha, 1.0, dark))), half(alpha)) * color.a;
}
