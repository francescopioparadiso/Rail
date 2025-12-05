from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
import sqlite3
import os


class trains:
    def __init__(self):
        self.db_path = os.path.join(os.path.dirname(__file__), "database.db")
        self.trenitalia_list_api = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/"
        self.trenitalia_trainInfo_api = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/"
        self.italo_trainInfo_api = "https://italoinviaggio.italotreno.it/api/RicercaTrenoService?TrainNumber="

    # ---------------- DB -------------------
    def create_database(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # drop table if exists
        cursor.execute("DROP TABLE IF EXISTS train_data")

        # create table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS train_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trainNumber INTEGER,
                numStations INTEGER,
                subTitle TEXT
            )
        """)
        conn.commit()
        conn.close()

    def save_to_database(self, trainNumber, numStations, subTitle):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # check for duplicates
        cursor.execute("SELECT COUNT(*) FROM train_data WHERE trainNumber = ?",
                       (trainNumber,))
        if cursor.fetchone()[0] > 0:
            conn.close()
            return
        
        # insert new record
        cursor.execute("INSERT INTO train_data (trainNumber, numStations, subTitle) VALUES (?, ?, ?)",
                       (int(trainNumber), numStations, subTitle))
        conn.commit()
        conn.close()

    # ---------------- API -------------------
    def trenitalia_parameter_fetcher(self, trainNumber: str, parameter: str):
        try:
            url = f"{self.trenitalia_list_api}{trainNumber}"
            response = requests.get(url, timeout=5)
        except:
            return None

        data1 = [row for row in response.text.split("\n") if row]

        data2 = []
        for datum in data1:
            parts = datum.split("|")[1].split("-")
            if len(parts) == 3:
                data2.append(f"{parts[1]}/{parts[0]}/{parts[2]}")

        parameterList = {}
        for v in data2:
            try:
                self.url = f"{self.trenitalia_trainInfo_api}{v}"
                res = requests.get(self.url, timeout=5)
                data = res.json()
                parameterList[self.url] = data.get(parameter)
            except:
                continue

        return parameterList

    # ------------- NEW PARALLEL VERSION ----------------
    def process_single_train(self, train_number):
        train_number_str = str(train_number)
        listTrains = self.trenitalia_parameter_fetcher(train_number_str, "subTitle")
        stations = self.trenitalia_parameter_fetcher(train_number_str, "fermate")
        numStations = len(stations[self.url]) if stations and self.url in stations else 0

        if not listTrains:
            return f"{train_number_str} → no data"

        for train in listTrains:
            issue = listTrains[train]
            if issue:
                self.save_to_database(train_number_str, numStations, issue)
                return f"Saved {train_number_str} -> {issue} with {numStations} stations"

        return f"{train_number_str} → no issue found"

    def trenitalia_issues_parallel(self, min_train, max_train, workers=20):
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(self.process_single_train, t)
                       for t in range(min_train, max_train)]
            for f in as_completed(futures):
                print(f.result())


if __name__ == "__main__":
    model = trains()
    model.create_database()
    model.trenitalia_issues_parallel(600, 30000, workers=50)