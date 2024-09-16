gpio:pinMode(27,0)
function update()
  if gpio:read(27) then 
      gcs:send_text(0, "Leak Detected!")
  end
  return update, 5000
end
return update() -- run immediately before starting to reschedule