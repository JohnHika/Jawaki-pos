# Axon POS Desktop

This is the independent desktop application for Axon POS. It is a fresh desktop workspace inspired by the product areas in the mobile POS, with a layout designed for keyboard, mouse, and larger screens.

## Included workspace areas

- Overview dashboard with sales and activity summaries
- Point of sale catalog, search, categories, cart, and payment confirmation
- Product catalog with stock and status visibility
- Customer list and customer metrics
- Inventory stock levels and reorder attention
- Reports and operating insights

The first desktop build uses local sample state so the experience can be reviewed independently. Backend synchronization, authentication, and production data wiring are the next integration layer.

## Run locally

From this folder:

```bash
flutter pub get
flutter run -d windows
```

Native release packages are built by `.github/workflows/build-desktop-app.yml` for Windows, macOS, and Linux.
