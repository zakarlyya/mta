import time

import requests
from google.transit import gtfs_realtime_pb2

FEED_URL = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace"
STOP_ID = "A49N"  # Ralph Av, Manhattan-bound
LINES = {"A", "C"}


def next_trains():
    resp = requests.get(FEED_URL, timeout=10)
    resp.raise_for_status()
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(resp.content)

    now = time.time()
    arrivals = []
    for entity in feed.entity:
        if not entity.HasField("trip_update"):
            continue
        trip = entity.trip_update.trip
        if trip.route_id not in LINES:
            continue
        for stu in entity.trip_update.stop_time_update:
            if stu.stop_id != STOP_ID:
                continue
            t = stu.arrival.time or stu.departure.time
            if t >= now:
                arrivals.append((t, trip.route_id, trip.trip_id))
    return feed.header.timestamp, sorted(arrivals)


if __name__ == "__main__":
    feed_ts, arrivals = next_trains()
    print(f"Feed updated {int(time.time() - feed_ts)}s ago")
    for t, route, trip_id in arrivals[:5]:
        mins = int((t - time.time()) // 60)
        print(f"{route}  {time.strftime('%I:%M:%S %p', time.localtime(t))}  ({mins} min)  {trip_id}")
    if not arrivals:
        print("No upcoming trains found")
