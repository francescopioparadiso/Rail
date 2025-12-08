# Rail - Il tuo viaggio, semplificato.

[![iOS 26+](https://img.shields.io/badge/iOS-26.0%2B-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-3F88F9.svg?style=flat&logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**Rail** è l'applicazione definitiva per il pendolare moderno. Nata dall'esigenza di avere informazioni chiare e precise, Rail unisce il monitoraggio dei treni in tempo reale con funzionalità social uniche per i viaggi di gruppo, il tutto racchiuso in un design nativo ed essenziale.

## 📱 Screenshots

<p float="left">
  <img src="Thumbnails/screen1.png" width="200" />
  <img src="Thumbnails/screen2.png" width="200" />
  <img src="Thumbnails/screen3.png" width="200" />
  <img src="Thumbnails/screen4.png" width="200" />
</p>

## ✨ Funzionalità Chiave

* **Monitoraggio Live:** Tracking in tempo reale di orari, ritardi, binari e cancellazioni.
* **Gestione Gruppi ("I tuoi Posti"):** Un sistema intuitivo per assegnare e visualizzare le carrozze e i posti a sedere di tutti i compagni di viaggio.
* **Contesto Intelligente:** Integrazione con servizi meteo per visualizzare le condizioni atmosferiche previste ad ogni singola fermata intermedia.
* **UI Nativa e Fluida:** Interfaccia sviluppata interamente in SwiftUI seguendo le Human Interface Guidelines di Apple.

## 🛠 Tech Stack & Architettura

Il progetto è sviluppato sfruttando le potenzialità di **Swift 6.2**, adottando un approccio pragmatico che combina le più recenti API Apple con una solida gestione dei dati legacy.

* **Linguaggio:** Swift 6.2
* **UI Framework:** SwiftUI
* **Architettura:** MVVM (Model-View-ViewModel) con separazione della logica di business in un Functional Core dedicato.
* **Concurrency Ibrida:**
    * Adozione di **Async/Await** per l'integrazione asincrona dei servizi moderni (come *WeatherKit* e *OpenMeteo*).
    * Utilizzo strategico di **Grand Central Dispatch (DispatchGroup)** per orchestrare e sincronizzare chiamate parallele verso provider multipli (Italo/Trenitalia).
* **Networking & Data:**
    * Integrazione REST API eterogenee tramite `URLSession`.
    * **Parsing Resiliente:** Utilizzo di `JSONSerialization` per la manipolazione manuale di strutture dati complesse e non standardizzate.
    * **Database Locale:** Lettura ottimizzata di file **CSV** per la risoluzione offline di coordinate e nomi stazioni.
* **Servizi Apple:** Integrazione profonda con `CoreLocation`, `MapKit` e `WeatherKit`.

### Sfide Tecniche Risolte
* **Normalizzazione Multi-Provider:** Implementazione di un layer di astrazione (Logic) che unifica le risposte JSON strutturalmente diverse di provider differenti in un unico modello dati coerente per l'UI.
* **Algoritmi Custom:** Sviluppo di logiche proprietarie per la conversione e normalizzazione dei binari (es. conversione numeri Romani/Arabi) e calcolo delle distanze geospaziali.
* **Ottimizzazione Performance:** Gestione di richieste multiple simultanee senza bloccare il thread principale, garantendo un'interfaccia sempre reattiva anche durante il fetch dei dati.

## 📄 Licenza

Questo progetto è distribuito sotto licenza **GNU GPLv3**.
Sei libero di studiare, modificare e utilizzare il codice, ma qualsiasi lavoro derivato distribuito deve rimanere open source sotto la stessa licenza. Vedi il file `LICENSE` per maggiori dettagli.

## 📬 Contatti

Sei un recruiter o uno sviluppatore interessato al progetto?
Sarei felice di discutere le scelte architetturali o ricevere feedback sul codice.

🌐 **Website:** [francescoparadiso.com](https://www.francescoparadiso.com)

🔗 **LinkedIn:** [Francesco Pio Paradiso](https://www.linkedin.com/in/francescopioparadiso)

## 🚀 Download

Scarica Rail direttamente dall'App Store e inizia a viaggiare meglio.

[<img src="https://upload.wikimedia.org/wikipedia/commons/3/3c/Download_on_the_App_Store_Badge.svg" width="200">](https://apps.apple.com/us/app/rail/id6755895103)
