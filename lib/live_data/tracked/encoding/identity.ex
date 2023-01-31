defmodule LiveData.Tracked.Encoding.Identity do

  def new do
    nil
  end

  def format(ops, nil) do
    {ops, nil}
  end

end
