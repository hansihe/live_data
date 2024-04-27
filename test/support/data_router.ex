defmodule LiveData.Test.DataRouter do
  use LiveData.Router

  data("/testing", LiveData.Test.TestingData)
end
