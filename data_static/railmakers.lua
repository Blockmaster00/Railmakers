local functions = tm.os.DoFile("functions")

local r = {}

local track_width = 1.6     --space between the rails
local rail_thickness = 0.25 --thickness of the rails
local rail_height = 0.3     --height of the rails
local uv_scale = 1          --scale for UV mapping

-- Procedural rail‐mesh exporter using helper “add” functions
-- Assumes these globals are defined:
--   splinePoints     : array of tm.vector3 world-space points
--   track_width      : distance between the two rails’ centers
--   rail_height      : height of the rail above the track surface
--   rail_thickness   : thickness of the rail
--   uv_scale         : how tightly the rail texture tiles along length
--   pivot            : tm.vector3 world-space origin for your OBJ
--   functions        : table with Normalize, Dot, QuaternionFromTo, RotateVectorByQuaternion
--   tm.vector3       : vector3 API
--   tm.os, tm.physics: File & mesh API



local function preparePoints(points)
    local newPoints = {}
    table.insert(newPoints, points[1])
    for i = 1, #points do
        table.insert(newPoints, points[i])
    end
    table.insert(newPoints, points[#points])
    return newPoints
end



local function buildRailCoroutine(side, splinePoints, pivot, addV, addUV, addN, quad)
    local forward = tm.vector3.Create(0, 0, 1)
    local totalLen, halfW = 0, track_width * 0.5

    -- 1) Precompute sections (no yields)
    local sections = {}
    for i, p in ipairs(splinePoints) do
        local dir = (i == #splinePoints) and functions.Normalize(p - splinePoints[i - 1])
            or functions.Normalize(splinePoints[i + 1] - p)
        local rot = functions.QuaternionFromTo(forward, dir)
        local function L(x, y, z)
            return functions.RotateVectorByQuaternion(tm.vector3.Create(x, y, z), rot) + p - pivot
        end
        local outerX, innerX = side * halfW, side * (halfW + rail_thickness)
        sections[i] = {
            pos = p,
            rot = rot,
            pts = { L(outerX, rail_height, 0), L(innerX, rail_height, 0),
                L(innerX, 0, 0), L(outerX, 0, 0) }
        }
    end

    -- 2) Bake vertices once per point (no yields)
    for _, sec in ipairs(sections) do
        sec.idx = {}
        for vi, pt in ipairs(sec.pts) do sec.idx[vi] = addV(pt) end
    end

    -- 3) Incrementally build mesh, yielding each segment
    for i = 1, #sections - 1 do
        local cur, nxt                 = sections[i], sections[i + 1]
        local seg                      = (nxt.pos - cur.pos).Magnitude()
        local v0, totalLen             = totalLen * uv_scale, totalLen + seg
        local v1                       = totalLen * uv_scale

        local verts, uvs, norms, faces = {}, {}, {}, {}
        local vCount, uvCount, nCount  = 0, 0, 0

        -- UVs for this slice
        cur.uv                         = {
            addUV(0, v0), addUV(1, v0),
            addUV(1, v0), addUV(0, v0),
        }
        nxt.uv                         = {
            addUV(0, v1), addUV(1, v1),
            addUV(1, v1), addUV(0, v1),
        }

        -- normals
        local nTop                     = addN(0, 1, 0)
        local nBot                     = addN(0, -1, 0)

        -- world-space side normals
        local outN                     = functions.RotateVectorByQuaternion(
            tm.vector3.Create(side, 0, 0), cur.rot
        )
        local inN                      = functions.RotateVectorByQuaternion(
            tm.vector3.Create(-side, 0, 0), cur.rot
        )
        local nOut                     = addN(outN.x, outN.y, outN.z)
        local nIn                      = addN(inN.x, inN.y, inN.z)

        local flip                     = side < 0

        -- Top quad
        if not flip then
            quad(           -- left rail winding
                cur.idx[2], -- p1
                cur.idx[1], -- p2
                nxt.idx[1], -- p3
                nxt.idx[2], -- p4
                nTop,
                cur.uv[2], nxt.uv[2], nxt.uv[1], cur.uv[1]
            )
        else
            quad( -- right rail: reverse p1↔p2 & p3↔p4
                cur.idx[1],
                cur.idx[2],
                nxt.idx[2],
                nxt.idx[1],
                nTop,
                cur.uv[1], nxt.uv[1], nxt.uv[2], cur.uv[2]
            )
        end

        -- Bottom quad (very similar)
        if not flip then
            quad(
                cur.idx[4],
                cur.idx[3],
                nxt.idx[3],
                nxt.idx[4],
                nBot,
                cur.uv[4], nxt.uv[4], nxt.uv[3], cur.uv[3]
            )
        else
            quad(
                cur.idx[3],
                cur.idx[4],
                nxt.idx[4],
                nxt.idx[3],
                nBot,
                cur.uv[3], nxt.uv[3], nxt.uv[4], cur.uv[4]
            )
        end

        -- compute whether we must flip winding for this rail
        local flipSide = (side > 0)

        -- Outer side (between pts 4→1 and 4→1 of next slice)
        do
            -- the four corner indices in natural order
            local p1, p2, p3, p4 =
                cur.idx[4], -- outer-bottom current
                cur.idx[1], -- outer-top current
                nxt.idx[1], -- outer-top next
                nxt.idx[4]  -- outer-bottom next

            -- their matching UVs
            local u1, u2, u3, u4 =
                cur.uv[4], cur.uv[1], nxt.uv[1], nxt.uv[4]

            if flipSide then
                -- swap p1<->p2 and p3<->p4
                p1, p2, p3, p4 = p2, p1, p4, p3
                u1, u2, u3, u4 = u2, u1, u4, u3
            end

            quad(p1, p2, p3, p4, nOut, u1, u2, u3, u4)
        end

        -- Inner side (between pts 2→3 and 2→3 of next slice)
        do
            local p1, p2, p3, p4 =
                cur.idx[2], -- inner-top current
                cur.idx[3], -- inner-bottom current
                nxt.idx[3], -- inner-bottom next
                nxt.idx[2]  -- inner-top next

            local u1, u2, u3, u4 =
                cur.uv[2], cur.uv[3], nxt.uv[3], nxt.uv[2]

            if flipSide then
                p1, p2, p3, p4 = p2, p1, p4, p3
                u1, u2, u3, u4 = u2, u1, u4, u3
            end

            quad(p1, p2, p3, p4, nIn, u1, u2, u3, u4)
        end
        totalLen = totalLen + seg
        -- After finishing the 4 quads:
        coroutine.yield(i) -- pause here, back to caller
    end
end




function r.MakeRailGenerator(points)
    if #points < 4 then
        tm.os.Log("Railmakers: Not enough points to generate a rail")
        return
    end

    points = preparePoints(points)

    -- 1) Build the dense Catmull-Rom spline
    local splinePoints = {}
    for i = 2, #points - 2 do
        local dist     = tm.vector3.Distance(points[i], points[i + 1])
        local segments = math.ceil(dist / 3)
        for j = 1, segments do
            local t              = j / segments
            local p0, p1, p2, p3 = points[i - 1], points[i], points[i + 1], points[i + 2]
            local pos            = functions.CatmullRom(p0, p1, p2, p3, t)
            table.insert(splinePoints, pos)
        end
    end

    tm.os.Log("Railmakers: Generating rail with " .. #splinePoints .. " segments")
    local pivot                    = splinePoints[1]

    -- 2) Prepare OBJ buffers & helper functions
    local verts, uvs, norms, faces = {}, {}, {}, {}
    local vCount, uvCount, nCount  = 0, 0, 0

    local function addV(v3)
        vCount = vCount + 1
        verts[vCount] = string.format("v %.6f %.6f %.6f", v3.x, v3.y, v3.z)
        return vCount
    end

    local function addUV(u, v)
        uvCount = uvCount + 1
        uvs[uvCount] = string.format("vt %.6f %.6f", u, v)
        return uvCount
    end

    local function addN(x, y, z)
        nCount = nCount + 1
        norms[nCount] = string.format("vn %.6f %.6f %.6f", x, y, z)
        return nCount
    end

    local function quad(i1, i2, i3, i4, nIdx, uv1, uv2, uv3, uv4)
        -- triangle 1
        faces[#faces + 1] = string.format(
            "f %d/%d/%d %d/%d/%d %d/%d/%d",
            i1, uv1, nIdx, i2, uv2, nIdx, i3, uv3, nIdx
        )
        -- triangle 2
        faces[#faces + 1] = string.format(
            "f %d/%d/%d %d/%d/%d %d/%d/%d",
            i1, uv1, nIdx, i3, uv3, nIdx, i4, uv4, nIdx
        )
    end


    -- Return the coroutine
    return coroutine.create(function()
        buildRailCoroutine(-1, splinePoints, pivot, addV, addUV, addN, quad)
        tm.os.Log("Railmakers: Built first rail segment, yielding to next coroutine step")
        --coroutine.yield() -- optional pause between rails
        buildRailCoroutine(1, splinePoints, pivot, addV, addUV, addN, quad)
        -- After both rails: write & spawn
        tm.os.Log("Railmakers: Built " .. vCount .. " vertices, " .. uvCount .. " UVs, " .. nCount .. " normals, " .. #faces .. " faces")
        local out = { "# Rail", "o Rail" }
        for _, v in ipairs(verts) do out[#out + 1] = v end
        for _, vt in ipairs(uvs) do out[#out + 1] = vt end
        for _, vn in ipairs(norms) do out[#out + 1] = vn end
        for _, f in ipairs(faces) do out[#out + 1] = f end

        tm.os.Log("Railmakers: Writing rail mesh to file")
        tm.os.WriteAllText_Dynamic("rail.obj", table.concat(out, "\n"))
        return pivot
    end)
end

return r
