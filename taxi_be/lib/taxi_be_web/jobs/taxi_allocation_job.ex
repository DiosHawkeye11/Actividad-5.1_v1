defmodule TaxiBeWeb.TaxiAllocationJob do
  alias Mix.ProjectStack
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])
    {:ok, %{request: request}}
  end

  def handle_info(:step1, %{request: request} = state) do
    # Select a taxi

    task = Task.async(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)
    taxis = select_candidate_taxis(request)
    Task.await(task)
    Process.send(self(), :block1, [:nosuspend])



    {:noreply, %{request: request, candidates: taxis, estado: NoAceptado}}
  end

  def handle_info(:block1, %{request: request, candidates: taxis, estado: NoAceptado} = state) do
    if taxis !=[] do
      taxi = hd(taxis)
      # Forward request to taxi driver
      %{
        "pickup_address" => pickup_address,
        "dropoff_address" => dropoff_address,
        "booking_id" => booking_id
      } = request
      TaxiBeWeb.Endpoint.broadcast(
        "driver:" <> taxi.nickname,
        "booking_request",
         %{
           msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
           bookingId: booking_id
          })

      Process.send_after(self(), :timeout1, 60000)
      {:noreply, %{request: request, candidates: tl(taxis), contacted_taxi: taxi, estado: NoAceptado}}
    else
      %{"username" => username} = request
      TaxiBeWeb.Endpoint.broadcast("customer:" <> username,"booking_request",%{msg: "Hubo un error. May the Force Be with You!", })
        {:noreply, state}
    end
  end

  def handle_info(:timeout1, %{estado: NoAceptado} = state) do
    Process.send(self(), :block1, [:nosuspend])
    {:noreply, state}
  end

  def handle_info(:timeout1, %{estado: Aceptado} = state) do

    {:noreply, state}
  end

  def handle_cast({:process_accept, driver_username}, %{request: request, estado: NoAceptado} = state) do
    IO.inspect(request)
    %{"username" => username} = request
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "Tu taxi esta en camino"})
    #timer = 1500
    {:noreply, state |> Map.put(:estado, Aceptado)}
  end

  def handle_cast({:process_accept, driver_username}, %{estado: Aceptado} = state) do
    TaxiBeWeb.Endpoint.broadcast( "driver:" <> driver_username, "booking_notification", %{msg: "Tiempo límite alcanzado!"})
  end



  def handle_cast({:process_reject, driver_username}, state) do
    Process.send(self(), :block1, [:nosuspend])
    {:noreply, state}
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
     } = request

    coord1 = TaxiBeWeb.Geolocator.geocode(pickup_address)
    coord2 = TaxiBeWeb.Geolocator.geocode(dropoff_address)
    {distance, _duration} = TaxiBeWeb.Geolocator.distance_and_duration(coord1, coord2)
    {request, Float.ceil(distance/300)}
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request
   TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{msg: "Ride fare: #{fare}"})
  end

  def select_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "Yoda", latitude: 19.0319783, longitude: -98.2349368}, # Angelopolis
      %{nickname: "Anakin", latitude: 19.0061167, longitude: -98.2697737}, # Arcangeles
      %{nickname: "Obi-Wan", latitude: 19.0092933, longitude: -98.2473716} # Paseo Destino
    ]
  end
end
