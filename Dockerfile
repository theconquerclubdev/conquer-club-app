# Use the official Flutter image
FROM cirrusci/flutter:stable AS builder

# Set working directory
WORKDIR /app

# Copy your project files
COPY . .

# Get dependencies
RUN flutter pub get

# Build the web app
RUN flutter build web --release

# Use a lightweight web server to serve the files
FROM nginx:alpine

# Copy the built files from the builder stage
COPY --from=builder /app/build/web /usr/share/nginx/html

# Expose port 80
EXPOSE 80