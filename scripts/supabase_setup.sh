git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase supabase-repo
pushd supabase-repo
git sparse-checkout set --cone docker && git checkout master
popd

# Copy the compose files over to your project
cp -rf supabase-repo/docker/* ./supabase/ 
# Copy the fake env vars
cp supabase-repo/docker/.env.example ./supabase/.env
# Switch to your project directory
pushd supabase
# Pull the latest images
docker compose pull