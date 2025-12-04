# Rail - Il tuo viaggio, semplificato.

[![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-3F88F9.svg?style=flat&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![App Store](https://img.shields.io/badge/Download_on_the-App_Store-black.svg?logo=apple&logoColor=white)](LINK_ALLA_TUA_APP_SULL_STORE)

**Rail** è l'applicazione definitiva per il pendolare moderno. Nata dall'esigenza di avere informazioni chiare e precise, Rail unisce il monitoraggio dei treni in tempo reale con funzionalità social uniche per i viaggi di gruppo, il tutto racchiuso in un design nativo ed essenziale.

---

## 📱 Screenshots

<p float="left">
  <img src="path/to/screen4.jpg" width="200" />
  <img src="path/to/screen2.jpg" width="200" /> 
  <img src="path/to/screen1.jpg" width="200" />
  <img src="path/to/screen3.jpg" width="200" />
</p>

---

## ✨ Funzionalità Chiave

* **Monitoraggio Live:** Tracking in tempo reale di orari, ritardi, binari e cancellazioni.
* **Gestione Gruppi ("I tuoi Posti"):** Un sistema intuitivo per assegnare e visualizzare le carrozze e i posti a sedere di tutti i compagni di viaggio.
* **Contesto Intelligente:** Integrazione con servizi meteo per visualizzare le condizioni atmosferiche previste ad ogni singola fermata intermedia.
* **UI Nativa e Fluida:** Interfaccia sviluppata interamente in SwiftUI seguendo le Human Interface Guidelines di Apple.

---

## 🛠 Tech Stack & Architettura

Il progetto è stato sviluppato con un approccio moderno, privilegiando la pulizia del codice e le performance.

* **Linguaggio:** Swift 5.9
* **UI Framework:** SwiftUI
* **Architettura:** MVVM (Model-View-ViewModel) per una chiara separazione delle responsabilità.
* **Concurrency:** Async/Await per la gestione delle chiamate di rete asincrone.
* **Networking:** URLSession nativo (nessuna dipendenza esterna pesante) con gestione custom degli errori API.
* **Persistenza Dati:** FileManager/UserDefaults per il salvataggio locale sicuro delle configurazioni dei gruppi.
* **Servizi:** CoreLocation per la geolocalizzazione e il fetch dei dati meteo contestuali.

### Sfide Tecniche Risolte
* **Parsing Complesso:** Gestione e normalizzazione di dati ferroviari spesso frammentati o incompleti provenienti da API legacy.
* **Stati UI Dinamici:** Gestione fluida degli stati di caricamento, errore e "empty state" (scheletri di caricamento) per migliorare la percezione di velocità dell'app.
* **Privacy First:** Architettura progettata per processare i dati sensibili (nomi, posizioni) esclusivamente on-device.

---

## 👨‍💻 Accesso al Codice Sorgente

Questa repository funge da **portfolio e vetrina tecnica**.
Poiché l'applicazione è attualmente pubblicata e attiva sull'App Store, il codice sorgente completo è mantenuto in una repository privata.

**Sei un recruiter o un technical lead?**
Sarei felice di mostrarti l'architettura del progetto, discutere le scelte tecniche o fornirti accesso a parti del codice durante un colloquio tecnico.

📧 **Contattami:** [Tua Email]
🔗 **LinkedIn:** [Tuo Profilo LinkedIn]

---

## 🚀 Download

Scarica Rail direttamente dall'App Store e inizia a viaggiare meglio.

[<img src="https://upload.wikimedia.org/wikipedia/commons/3/3c/Download_on_the_App_Store_Badge.svg" width="200">](LINK_ALLA_TUA_APP_SULL_STORE)

---
*Developed with ❤️ in Italy.*
