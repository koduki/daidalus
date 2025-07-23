FROM ruby:3.2-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl https://sdk.cloud.google.com | bash
ENV PATH $PATH:/root/google-cloud-sdk/bin

# Install gemini-cli (assuming it will be available via npm or similar)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Copy Gemfile and install Ruby dependencies
COPY Gemfile* ./
RUN bundle install

# Copy application code
COPY . .

EXPOSE 4567

CMD ["ruby", "app.rb"]
