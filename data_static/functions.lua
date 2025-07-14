local m = {}


local function quat_mult(a, b)
    return tm.quaternion.Create(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    )
end

-- Function to perform Catmull-Rom interpolation for one segment
function m.CatmullRom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    local x = 0.5 * ((2 * p1.x) +
        (-p0.x + p2.x) * t +
        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)

    local y = 0.5 * ((2 * p1.y) +
        (-p0.y + p2.y) * t +
        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

    local z = 0.5 * ((2 * p1.z) +
        (-p0.z + p2.z) * t +
        (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2 +
        (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3)

    return tm.vector3.Create(x, y, z)
end

function m.Normalize(v)
    local length = v.Magnitude()
    if length == 0 then
        return tm.vector3.Create(0, 0, 0)
    end
    return tm.vector3.Create(v.x / length, v.y / length, v.z / length)
end

function m.QuaternionFromTo(from, to)
    local dot = from.Dot(to)
    if dot < -0.999999 then
        -- 180 degrees rotation
        return tm.quaternion.Create(0, 1, 0, 0) -- Arbitrary axis
    elseif dot > 0.999999 then
        return tm.quaternion.Create(0, 0, 0, 1) -- No rotation needed
    end

    local axis = from.Cross(to)
    local angle = math.acos(dot)
    return tm.quaternion.Create(axis.x * math.sin(angle / 2), axis.y * math.sin(angle / 2), axis.z * math.sin(angle / 2), math.cos(angle / 2))
end

function m.RotateVectorByQuaternion(v, q)
    local q_conjugate = tm.quaternion.Create(-q.x, -q.y, -q.z, q.w)
    local v_as_quat = tm.quaternion.Create(v.x, v.y, v.z, 0)

    local rotated_quat = quat_mult(quat_mult(q, v_as_quat), q_conjugate)
    local rotated = rotated_quat
    return tm.vector3.Create(rotated.x, rotated.y, rotated.z)
end

return m