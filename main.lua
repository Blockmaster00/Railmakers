local railmakers = tm.os.DoFile("railmakers")


-- splice splines into multiple segments that each get generated in their own update cycle
-- this is to avoid the game freezing when generating a spline with many segments


local points = {
    tm.vector3.Create(0, 300, 0),
    tm.vector3.Create(100, 300, 0),
    tm.vector3.Create(200, 300, 5),
    tm.vector3.Create(300, 300, 10),
    tm.vector3.Create(400, 300, 200),
}


local gen = railmakers.MakeRailGenerator(points)

function update()
    if gen then
        if coroutine.status(gen) ~= "dead" then
            local ok, stepOrErr = coroutine.resume(gen)
            if not ok then
                tm.os.Log("RailGen error:".. stepOrErr)
            else
                tm.os.Log("Built segment:".. tostring(stepOrErr))
            end
        elseif coroutine.status(gen) == "dead" then
            tm.os.Log("RailGen finished")
            tm.os.Log("loading rail mesh")
            tm.physics.AddMesh("data_dynamic_willNotBeUploadedToWorkshop/rail.obj", "rail")
            tm.physics.SpawnCustomObjectConcave(points[1], "rail", "")
            gen = nil -- reset generator
        end
    end
end